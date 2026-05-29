use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use sea_orm::{ActiveModelBehavior, ActiveModelTrait, ColumnTrait, EntityTrait, IntoActiveModel, PaginatorTrait, QueryFilter, QueryOrder, Set};
use uuid::Uuid;

use crate::{
    handlers::auth::{AppState, ApiResponse},
    models::{AddToQueueDto, ReorderQueueDto, UserQueueItemActiveModel, UserQueueItemColumn, UserQueueItemEntity, UserResponseDto, UserTrackEntity},
    services::{LibraryProvider, LibrarySyncService, cache_cover_url},
};

#[derive(Debug, serde::Serialize)]
pub struct QueueItemResponseDto {
    pub id: Uuid,
    pub user_track_id: Uuid,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<i32>,
    pub source: String,
    pub cover_url: Option<String>,
    pub position: i32,
    pub added_at: chrono::NaiveDateTime,
}

pub async fn get_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<Vec<QueueItemResponseDto>>>, StatusCode> {
    let queue_items = UserQueueItemEntity::find()
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .order_by_asc(UserQueueItemColumn::Position)
        .all(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut response_dtos = Vec::with_capacity(queue_items.len());
    for item in queue_items {
        let track = UserTrackEntity::find_by_id(item.user_track_id)
            .one(state.db())
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
            .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
        response_dtos.push(QueueItemResponseDto {
            id: item.id,
            user_track_id: item.user_track_id,
            track_id: track.provider_track_id,
            title: track.title,
            artist: track.artist,
            album: track.album_name.unwrap_or_default(),
            duration: track.duration,
            source: track.source,
            cover_url: cache_cover_url(track.cover_url),
            position: item.position,
            added_at: item.added_at,
        });
    }

    Ok(Json(ApiResponse::success(response_dtos)))
}

pub async fn add_to_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(add_dto): Json<AddToQueueDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    let provider = add_dto
        .source
        .parse::<LibraryProvider>()
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    let user_track = LibrarySyncService::ensure_user_track_from_input(
        state.db(),
        user.id,
        provider,
        &add_dto.track_id,
        &add_dto.title,
        &add_dto.artist,
        Some(&add_dto.album),
        Some(add_dto.duration),
        add_dto.cover_url.as_deref(),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Get the next position in the queue
    let next_position = UserQueueItemEntity::find()
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .count(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let queue_item = UserQueueItemActiveModel {
        user_id: Set(user.id),
        user_track_id: Set(user_track.id),
        position: Set(next_position as i32),
        ..UserQueueItemActiveModel::new()
    };

    queue_item.insert(&state.auth_service.db).await.map_err(|e| {
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(ApiResponse::success(true)))
}

pub async fn remove_from_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(queue_item_id): Path<String>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    let queue_item_id: Uuid = queue_item_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    // Find the item to get its position
    let queue_item = UserQueueItemEntity::find()
        .filter(UserQueueItemColumn::Id.eq(queue_item_id))
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let removed_position = match queue_item {
        Some(item) => item.position,
        None => return Ok(Json(ApiResponse::<bool> {
            success: false,
            data: None,
            message: Some("Queue item not found".to_string()),
        })),
    };

    // Delete the item
    UserQueueItemEntity::delete_by_id(queue_item_id)
        .exec(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Update positions of items that come after the removed item
    let items_to_update = UserQueueItemEntity::find()
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .filter(UserQueueItemColumn::Position.gt(removed_position))
        .all(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for item in items_to_update {
        let mut active_item = item.into_active_model();
        active_item.position = Set(active_item.position.unwrap() - 1);
        UserQueueItemEntity::update(active_item)
            .exec(&state.auth_service.db)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn reorder_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(queue_item_id): Path<String>,
    Json(reorder_dto): Json<ReorderQueueDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    let queue_item_id: Uuid = queue_item_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    // Get the current item
    let current_item = UserQueueItemEntity::find()
        .filter(UserQueueItemColumn::Id.eq(queue_item_id))
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let current_position = match &current_item {
        Some(item) => item.position,
        None => return Ok(Json(ApiResponse::<bool> {
            success: false,
            data: None,
            message: Some("Queue item not found".to_string()),
        })),
    };

    let new_position = reorder_dto.new_position;
    let max_position = UserQueueItemEntity::find()
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .count(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)? as i32 - 1;

    if new_position < 0 || new_position > max_position {
        return Ok(Json(ApiResponse::<bool> {
            success: false,
            data: None,
            message: Some("Invalid position".to_string()),
        }));
    }

    if current_position == new_position {
        return Ok(Json(ApiResponse::success(true)));
    }

    // Update the moved item's position
    let mut item_to_move = current_item.unwrap().into_active_model();
    item_to_move.position = Set(new_position);
    UserQueueItemEntity::update(item_to_move)
        .exec(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Update positions of other items
    if new_position > current_position {
        // Moving down: shift items between current_position+1 and new_position up
        let items_to_shift = UserQueueItemEntity::find()
            .filter(UserQueueItemColumn::UserId.eq(user.id))
            .filter(UserQueueItemColumn::Position.gt(current_position))
            .filter(UserQueueItemColumn::Position.lte(new_position))
            .all(&state.auth_service.db)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        for item in items_to_shift {
            if item.id != queue_item_id {
                let mut active_item = item.into_active_model();
                active_item.position = Set(active_item.position.unwrap() - 1);
                UserQueueItemEntity::update(active_item)
                    .exec(&state.auth_service.db)
                    .await
                    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            }
        }
    } else {
        // Moving up: shift items between new_position and current_position-1 down
        let items_to_shift = UserQueueItemEntity::find()
            .filter(UserQueueItemColumn::UserId.eq(user.id))
            .filter(UserQueueItemColumn::Position.gte(new_position))
            .filter(UserQueueItemColumn::Position.lt(current_position))
            .all(&state.auth_service.db)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        for item in items_to_shift {
            let mut active_item = item.into_active_model();
            active_item.position = Set(active_item.position.unwrap() + 1);
            UserQueueItemEntity::update(active_item)
                .exec(&state.auth_service.db)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        }
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn clear_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    UserQueueItemEntity::delete_many()
        .filter(UserQueueItemColumn::UserId.eq(user.id))
        .exec(&state.auth_service.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(true)))
}