use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use sea_orm::{
    ActiveModelTrait, ColumnTrait, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, Set, IntoActiveModel,
};
use sea_orm::prelude::Expr;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use tracing::{debug, error};
use uuid::Uuid;

use crate::handlers::auth::{AppState, ApiResponse};
use crate::models::{
    PlaylistEntity, PlaylistItemEntity, PlaylistResponseDto, CreatePlaylistDto, UpdatePlaylistDto,
    PlaylistItemResponseDto, AddPlaylistItemDto, ReorderPlaylistItemDto, UserResponseDto,
};

#[derive(Deserialize)]
pub struct GetPlaylistsQuery {
    pub page: Option<u64>,
    pub per_page: Option<u64>,
    pub search: Option<String>,
}

#[derive(Serialize)]
pub struct PlaylistListResponse {
    pub playlists: Vec<PlaylistResponseDto>,
    pub total: u64,
    pub page: u64,
    pub per_page: u64,
}

// Get all playlists for a user
pub async fn get_playlists(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetPlaylistsQuery>,
) -> Result<Json<ApiResponse<PlaylistListResponse>>, StatusCode> {
    debug!("Getting playlists for user: {}", user.id);

    let page = params.page.unwrap_or(1);
    let per_page = params.per_page.unwrap_or(20).min(100);

    let mut query = PlaylistEntity::find()
        .filter(crate::models::playlist::Column::UserId.eq(user.id));

    if let Some(search) = params.search {
        query = query.filter(crate::models::playlist::Column::Name.contains(&search));
    }

    let paginator = query
        .order_by_desc(crate::models::playlist::Column::UpdatedAt)
        .paginate(&state.auth_service.db, per_page);

    let total = paginator.num_items().await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let playlists = paginator
        .fetch_page(page - 1)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .into_iter()
        .map(|playlist| {
            let mut response: PlaylistResponseDto = playlist.into();
            // TODO: Set item_count by counting playlist items
            response.item_count = 0;
            response
        })
        .collect();

    let response = PlaylistListResponse {
        playlists,
        total,
        page,
        per_page,
    };

    Ok(Json(ApiResponse::success(response)))
}

// Create a new playlist
pub async fn create_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(create_dto): Json<CreatePlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    debug!("Creating playlist for user: {}", user.id);

    let now = chrono::Utc::now().naive_utc();
    let playlist = crate::models::playlist::ActiveModel {
        id: Set(Uuid::new_v4()),
        user_id: Set(user.id),
        name: Set(create_dto.name),
        description: Set(create_dto.description),
        is_public: Set(create_dto.is_public),
        created_at: Set(now),
        updated_at: Set(now),
    };

    let playlist = playlist.insert(&state.auth_service.db).await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let response: PlaylistResponseDto = playlist.into();
    Ok(Json(ApiResponse::success(response)))
}

// Get a specific playlist with its items
pub async fn get_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    debug!("Getting playlist {} for user: {}", playlist_id, user.id);

    let playlist = PlaylistEntity::find_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let playlist = match playlist {
        Some(p) => p,
        None => return Err(StatusCode::NOT_FOUND),
    };

    let response: PlaylistResponseDto = playlist.into();
    Ok(Json(ApiResponse::success(response)))
}

// Update a playlist
pub async fn update_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
    Json(update_dto): Json<UpdatePlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    debug!("Updating playlist {} for user: {}", playlist_id, user.id);

    let playlist = PlaylistEntity::find_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let mut playlist = match playlist {
        Some(p) => p.into_active_model(),
        None => return Err(StatusCode::NOT_FOUND),
    };

    if let Some(name) = update_dto.name {
        playlist.name = Set(name);
    }
    if let Some(description) = update_dto.description {
        playlist.description = Set(Some(description));
    }
    if let Some(is_public) = update_dto.is_public {
        playlist.is_public = Set(is_public);
    }
    playlist.updated_at = Set(chrono::Utc::now().naive_utc());

    let playlist = playlist.update(&state.auth_service.db).await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let response: PlaylistResponseDto = playlist.into();
    Ok(Json(ApiResponse::success(response)))
}

// Delete a playlist
pub async fn delete_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Deleting playlist {} for user: {}", playlist_id, user.id);

    let result = PlaylistEntity::delete_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .exec(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if result.rows_affected == 0 {
        return Err(StatusCode::NOT_FOUND);
    }

    Ok(Json(ApiResponse::success(true)))
}

// Get playlist items
pub async fn get_playlist_items(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<PlaylistItemResponseDto>>>, StatusCode> {
    debug!("Getting items for playlist {} for user: {}", playlist_id, user.id);

    // First verify the playlist belongs to the user
    let playlist = PlaylistEntity::find_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if playlist.is_none() {
        return Err(StatusCode::NOT_FOUND);
    }

    let items = PlaylistItemEntity::find()
        .filter(crate::models::playlist_item::Column::PlaylistId.eq(playlist_id))
        .order_by_asc(crate::models::playlist_item::Column::Position)
        .all(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let response_items: Vec<PlaylistItemResponseDto> = items.into_iter().map(|item| item.into()).collect();

    Ok(Json(ApiResponse::success(response_items)))
}

// Add item to playlist
pub async fn add_playlist_item(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
    Json(add_dto): Json<AddPlaylistItemDto>,
) -> Result<Json<ApiResponse<PlaylistItemResponseDto>>, StatusCode> {
    debug!("Adding item to playlist {} for user: {}", playlist_id, user.id);

    // First verify the playlist belongs to the user
    let playlist = PlaylistEntity::find_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if playlist.is_none() {
        return Err(StatusCode::NOT_FOUND);
    }

    // Check for circular dependency if adding a playlist
    if add_dto.item_type == "playlist" {
        if let Err(e) = check_circular_dependency(&state, playlist_id, &add_dto.item_id).await {
            return Err(e);
        }
    }

    // Get the next position
    let next_position = PlaylistItemEntity::find()
        .filter(crate::models::playlist_item::Column::PlaylistId.eq(playlist_id))
        .count(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let position = add_dto.position.unwrap_or(next_position as i32);

    let item = crate::models::playlist_item::ActiveModel {
        id: Set(Uuid::new_v4()),
        playlist_id: Set(playlist_id),
        item_type: Set(add_dto.item_type),
        item_id: Set(add_dto.item_id),
        position: Set(position),
        added_at: Set(chrono::Utc::now().naive_utc()),
        // Store track/playlist details
        title: Set(add_dto.title),
        artist: Set(add_dto.artist),
        album: Set(add_dto.album),
        duration: Set(add_dto.duration),
        source: Set(add_dto.source),
        cover_url: Set(add_dto.cover_url),
        playlist_name: Set(add_dto.playlist_name),
    };

    let item = item.insert(&state.auth_service.db).await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let response: PlaylistItemResponseDto = item.into();
    Ok(Json(ApiResponse::success(response)))
}

// Remove item from playlist
pub async fn remove_playlist_item(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path((playlist_id, item_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Removing item {} from playlist {} for user: {}", item_id, playlist_id, user.id);

    // First verify the playlist belongs to the user
    let playlist = PlaylistEntity::find_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if playlist.is_none() {
        return Err(StatusCode::NOT_FOUND);
    }

    let result = PlaylistItemEntity::delete_by_id(item_id)
        .filter(crate::models::playlist_item::Column::PlaylistId.eq(playlist_id))
        .exec(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if result.rows_affected == 0 {
        return Err(StatusCode::NOT_FOUND);
    }

    Ok(Json(ApiResponse::success(true)))
}

// Reorder playlist item
pub async fn reorder_playlist_item(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path((playlist_id, item_id)): Path<(Uuid, Uuid)>,
    Json(reorder_dto): Json<ReorderPlaylistItemDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("Reordering item {} in playlist {} for user: {}", item_id, playlist_id, user.id);

    // First verify the playlist belongs to the user
    let playlist = PlaylistEntity::find_by_id(playlist_id)
        .filter(crate::models::playlist::Column::UserId.eq(user.id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if playlist.is_none() {
        return Err(StatusCode::NOT_FOUND);
    }

    // Get the current item
    let current_item = PlaylistItemEntity::find_by_id(item_id)
        .filter(crate::models::playlist_item::Column::PlaylistId.eq(playlist_id))
        .one(&state.auth_service.db)
        .await
        .map_err(|e| {
            error!("Database error: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let current_item = match current_item {
        Some(item) => item,
        None => return Err(StatusCode::NOT_FOUND),
    };

    let old_position = current_item.position;
    let new_position = reorder_dto.new_position;

    if old_position == new_position {
        return Ok(Json(ApiResponse::success(true)));
    }

    // Update positions of other items
    if new_position > old_position {
        // Moving down: shift items between old_position+1 and new_position up by 1
        PlaylistItemEntity::update_many()
            .col_expr(
                crate::models::playlist_item::Column::Position,
                Expr::col(crate::models::playlist_item::Column::Position).sub(1),
            )
            .filter(crate::models::playlist_item::Column::PlaylistId.eq(playlist_id))
            .filter(crate::models::playlist_item::Column::Position.gt(old_position))
            .filter(crate::models::playlist_item::Column::Position.lte(new_position))
            .exec(&state.auth_service.db)
            .await
            .map_err(|e| {
                error!("Database error: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    } else {
        // Moving up: shift items between new_position and old_position-1 down by 1
        PlaylistItemEntity::update_many()
            .col_expr(
                crate::models::playlist_item::Column::Position,
                Expr::col(crate::models::playlist_item::Column::Position).add(1),
            )
            .filter(crate::models::playlist_item::Column::PlaylistId.eq(playlist_id))
            .filter(crate::models::playlist_item::Column::Position.gte(new_position))
            .filter(crate::models::playlist_item::Column::Position.lt(old_position))
            .exec(&state.auth_service.db)
            .await
            .map_err(|e| {
                error!("Database error: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }

    // Update the current item's position
    let mut current_item = current_item.into_active_model();
    current_item.position = Set(new_position);
    current_item.update(&state.auth_service.db).await.map_err(|e| {
        error!("Database error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(ApiResponse::success(true)))
}

// Check for circular dependency when adding a playlist to another playlist
async fn check_circular_dependency(
    state: &AppState,
    target_playlist_id: Uuid,
    source_playlist_id: &str,
) -> Result<(), StatusCode> {
    let source_playlist_uuid = match Uuid::parse_str(source_playlist_id) {
        Ok(uuid) => uuid,
        Err(_) => return Err(StatusCode::BAD_REQUEST),
    };

    if target_playlist_id == source_playlist_uuid {
        return Err(StatusCode::BAD_REQUEST); // Can't add playlist to itself
    }

    // Use DFS to check for circular dependency
    let mut visited = HashSet::new();
    let mut stack = vec![source_playlist_uuid];

    while let Some(current_playlist_id) = stack.pop() {
        if current_playlist_id == target_playlist_id {
            return Err(StatusCode::BAD_REQUEST); // Circular dependency found
        }

        if visited.contains(&current_playlist_id) {
            continue;
        }
        visited.insert(current_playlist_id);

        // Get all playlists that this playlist contains
        let child_playlists = PlaylistItemEntity::find()
            .filter(crate::models::playlist_item::Column::ItemType.eq("playlist"))
            .filter(crate::models::playlist_item::Column::PlaylistId.eq(current_playlist_id))
            .all(&state.auth_service.db)
            .await
            .map_err(|e| {
                error!("Database error: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        for child in child_playlists {
            if let Ok(child_uuid) = Uuid::parse_str(&child.item_id) {
                stack.push(child_uuid);
            }
        }
    }

    Ok(())
}
