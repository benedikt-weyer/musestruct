use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use sea_orm::{EntityTrait, QueryFilter, ColumnTrait, Set, ActiveModelTrait, QueryOrder, PaginatorTrait, IntoActiveModel};
use tracing::{debug, error};
use uuid::Uuid;

use crate::{
    handlers::auth::{AppState, ApiResponse},
    models::{QueueItemEntity, AddToQueueDto, ReorderQueueDto, QueueItemResponseDto, UserResponseDto},
};

pub async fn get_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<Vec<QueueItemResponseDto>>>, StatusCode> {
    debug!("Getting queue for user: {}", user.id);

    let queue_items = QueueItemEntity::find()
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .order_by_asc(crate::models::queue_item::Column::Position)
        .all(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let response_dtos: Vec<QueueItemResponseDto> = queue_items
        .into_iter()
        .map(|item| item.into())
        .collect();

    Ok(Json(ApiResponse::success(response_dtos)))
}

pub async fn add_to_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(add_dto): Json<AddToQueueDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Adding track to queue for user: {}", user.id);

    // Get the next position in the queue
    let next_position = QueueItemEntity::find()
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .count(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let queue_item = crate::models::queue_item::ActiveModel {
        user_id: Set(user.id),
        track_id: Set(add_dto.track_id.clone()),
        title: Set(add_dto.title.clone()),
        artist: Set(add_dto.artist.clone()),
        album: Set(add_dto.album.clone()),
        duration: Set(add_dto.duration),
        source: Set(add_dto.source.clone()),
        cover_url: Set(add_dto.cover_url.clone()),
        position: Set(next_position as i32),
        ..Default::default()
    };

    queue_item.insert(&state.auth_service.db).await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(ApiResponse::success(true)))
}

pub async fn remove_from_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(queue_item_id): Path<String>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Removing track from queue for user: {}", user.id);

    let queue_item_id: Uuid = queue_item_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    // Find the item to get its position
    let queue_item = QueueItemEntity::find()
        .filter(crate::models::queue_item::Column::Id.eq(queue_item_id))
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let removed_position = match queue_item {
        Some(item) => item.position,
        None => return Ok(Json(ApiResponse::<bool> {
            success: false,
            data: None,
            message: Some("Queue item not found".to_string()),
        })),
    };

    // Delete the item
    QueueItemEntity::delete_by_id(queue_item_id)
        .exec(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Update positions of items that come after the removed item
    let items_to_update = QueueItemEntity::find()
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .filter(crate::models::queue_item::Column::Position.gt(removed_position))
        .all(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    for item in items_to_update {
        let mut active_item = item.into_active_model();
        active_item.position = Set(active_item.position.unwrap() - 1);
        QueueItemEntity::update(active_item).exec(&state.auth_service.db).await.map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn reorder_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(queue_item_id): Path<String>,
    Json(reorder_dto): Json<ReorderQueueDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Reordering queue for user: {}", user.id);

    let queue_item_id: Uuid = queue_item_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    // Get the current item
    let current_item = QueueItemEntity::find()
        .filter(crate::models::queue_item::Column::Id.eq(queue_item_id))
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let current_position = match &current_item {
        Some(item) => item.position,
        None => return Ok(Json(ApiResponse::<bool> {
            success: false,
            data: None,
            message: Some("Queue item not found".to_string()),
        })),
    };

    let new_position = reorder_dto.new_position;
    let max_position = QueueItemEntity::find()
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .count(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })? as i32 - 1;

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
    QueueItemEntity::update(item_to_move).exec(&state.auth_service.db).await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // Update positions of other items
    if new_position > current_position {
        // Moving down: shift items between current_position+1 and new_position up
        let items_to_shift = QueueItemEntity::find()
            .filter(crate::models::queue_item::Column::UserId.eq(user.id))
            .filter(crate::models::queue_item::Column::Position.gt(current_position))
            .filter(crate::models::queue_item::Column::Position.lte(new_position))
            .all(&state.auth_service.db)
            .await
            .map_err(|e| {
                error!("Database error: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        for item in items_to_shift {
            if item.id != queue_item_id {
                let mut active_item = item.into_active_model();
                active_item.position = Set(active_item.position.unwrap() - 1);
                QueueItemEntity::update(active_item).exec(&state.auth_service.db).await.map_err(|e| {
                    error!("Database error: {}", e);
                    StatusCode::INTERNAL_SERVER_ERROR
                })?;
            }
        }
    } else {
        // Moving up: shift items between new_position and current_position-1 down
        let items_to_shift = QueueItemEntity::find()
            .filter(crate::models::queue_item::Column::UserId.eq(user.id))
            .filter(crate::models::queue_item::Column::Position.gte(new_position))
            .filter(crate::models::queue_item::Column::Position.lt(current_position))
            .all(&state.auth_service.db)
            .await
            .map_err(|e| {
                error!("Database error: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        for item in items_to_shift {
            let mut active_item = item.into_active_model();
            active_item.position = Set(active_item.position.unwrap() + 1);
            QueueItemEntity::update(active_item).exec(&state.auth_service.db).await.map_err(|e| {
                error!("Database error: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
        }
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn clear_queue(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Clearing queue for user: {}", user.id);

    QueueItemEntity::delete_many()
        .filter(crate::models::queue_item::Column::UserId.eq(user.id))
        .exec(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(ApiResponse::success(true)))
}