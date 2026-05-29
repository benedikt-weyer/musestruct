use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use sea_orm::{ActiveModelTrait, ColumnTrait, EntityTrait, IntoActiveModel, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect, Set};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use tracing::error;
use uuid::Uuid;

use crate::{
    handlers::auth::{ApiResponse, AppState},
    models::{
        UserPlaylistActiveModel, UserPlaylistColumn, UserPlaylistEntity, UserPlaylistItemActiveModel,
        UserPlaylistItemColumn, UserPlaylistItemEntity, UserPlaylistModel, UserResponseDto,
        UserTrackColumn, UserTrackEntity,
    },
    services::{LibraryProvider, LibrarySyncService, cache_cover_url},
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

#[derive(Deserialize)]
pub struct CreatePlaylistDto {
    pub name: String,
    pub description: Option<String>,
    pub is_public: bool,
}

#[derive(Deserialize)]
pub struct UpdatePlaylistDto {
    pub name: Option<String>,
    pub description: Option<String>,
    pub is_public: Option<bool>,
}

#[derive(Serialize)]
pub struct PlaylistResponseDto {
    pub id: Uuid,
    pub canonical_playlist_id: Option<Uuid>,
    pub name: String,
    pub description: Option<String>,
    pub source: Option<String>,
    pub provider_playlist_id: Option<String>,
    pub is_public: bool,
    pub is_read_only: bool,
    pub is_watched: bool,
    pub last_synced_at: Option<chrono::NaiveDateTime>,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
    pub item_count: i32,
    pub preview_cover_urls: Vec<String>,
}

#[derive(Deserialize)]
pub struct AddPlaylistItemDto {
    pub item_type: String,
    pub item_id: String,
    pub position: Option<i32>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub duration: Option<i32>,
    pub source: Option<String>,
    pub cover_url: Option<String>,
    pub playlist_name: Option<String>,
}

#[derive(Deserialize)]
pub struct ReorderPlaylistItemDto {
    pub new_position: i32,
}

#[derive(Deserialize)]
pub struct ImportCanonicalPlaylistDto {
    pub preferred_source: Option<String>,
    pub watched: Option<bool>,
}

#[derive(Deserialize)]
pub struct ImportProviderPlaylistDto {
    pub source: String,
    pub playlist_id: String,
    pub name: String,
    pub description: Option<String>,
    pub owner: Option<String>,
    pub cover_url: Option<String>,
    pub is_public: Option<bool>,
    pub watched: Option<bool>,
}

#[derive(Serialize)]
pub struct PlaylistItemResponseDto {
    pub id: Uuid,
    pub item_type: String,
    pub item_id: String,
    pub user_track_id: Option<Uuid>,
    pub position: i32,
    pub added_at: chrono::NaiveDateTime,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub duration: Option<i32>,
    pub source: Option<String>,
    pub cover_url: Option<String>,
    pub is_playlist: bool,
    pub playlist_name: Option<String>,
}

pub async fn get_playlists(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetPlaylistsQuery>,
) -> Result<Json<ApiResponse<PlaylistListResponse>>, StatusCode> {
    let page = params.page.unwrap_or(1);
    let per_page = params.per_page.unwrap_or(20).min(100);

    let mut query = UserPlaylistEntity::find().filter(UserPlaylistColumn::UserId.eq(user.id));
    if let Some(search) = params.search.filter(|value| !value.trim().is_empty()) {
        query = query.filter(UserPlaylistColumn::Name.contains(&search));
    }

    let paginator = query
        .order_by_desc(UserPlaylistColumn::UpdatedAt)
        .paginate(state.db(), per_page);
    let total = paginator.num_items().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let playlist_models = paginator.fetch_page(page - 1).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut playlists = Vec::with_capacity(playlist_models.len());
    for playlist in playlist_models {
        let item_count = UserPlaylistItemEntity::find()
            .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist.id))
            .count(state.db())
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        playlists.push(playlist_model_response(state.db(), playlist, item_count as i32).await?);
    }

    Ok(Json(ApiResponse::success(PlaylistListResponse {
        playlists,
        total,
        page,
        per_page,
    })))
}

pub async fn create_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(create_dto): Json<CreatePlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    let playlist = UserPlaylistActiveModel {
        user_id: Set(user.id),
        name: Set(create_dto.name),
        description: Set(create_dto.description),
        is_public: Set(create_dto.is_public),
        ..Default::default()
    }
    .insert(state.db())
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(
        playlist_model_response(state.db(), playlist, 0).await?,
    )))
}

pub async fn get_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    let playlist = UserPlaylistEntity::find_by_id(playlist_id)
        .filter(UserPlaylistColumn::UserId.eq(user.id))
        .one(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    let item_count = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist.id))
        .count(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(
        playlist_model_response(state.db(), playlist, item_count as i32).await?,
    )))
}

pub async fn update_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
    Json(update_dto): Json<UpdatePlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    let playlist = UserPlaylistEntity::find_by_id(playlist_id)
        .filter(UserPlaylistColumn::UserId.eq(user.id))
        .one(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    if playlist.is_read_only {
        return Err(StatusCode::FORBIDDEN);
    }

    let mut active = playlist.into_active_model();
    if let Some(name) = update_dto.name {
        active.name = Set(name);
    }
    if let Some(description) = update_dto.description {
        active.description = Set(Some(description));
    }
    if let Some(is_public) = update_dto.is_public {
        active.is_public = Set(is_public);
    }
    active.updated_at = Set(chrono::Utc::now().naive_utc());

    let playlist = active.update(state.db()).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let item_count = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist.id))
        .count(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(
        playlist_model_response(state.db(), playlist, item_count as i32).await?,
    )))
}

pub async fn delete_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    let result = UserPlaylistEntity::delete_many()
        .filter(UserPlaylistColumn::Id.eq(playlist_id))
        .filter(UserPlaylistColumn::UserId.eq(user.id))
        .exec(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if result.rows_affected == 0 {
        return Err(StatusCode::NOT_FOUND);
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn get_playlist_items(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<PlaylistItemResponseDto>>>, StatusCode> {
    ensure_user_playlist_owner(state.db(), user.id, playlist_id).await?;

    let items = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .order_by_asc(UserPlaylistItemColumn::Position)
        .all(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut response_items = Vec::with_capacity(items.len());
    for item in items {
        response_items.push(playlist_item_response(state.db(), item).await?);
    }

    Ok(Json(ApiResponse::success(response_items)))
}

pub async fn add_playlist_item(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
    Json(add_dto): Json<AddPlaylistItemDto>,
) -> Result<Json<ApiResponse<PlaylistItemResponseDto>>, StatusCode> {
    let playlist = ensure_mutable_playlist(state.db(), user.id, playlist_id).await?;

    let next_position = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .count(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)? as i32;
    let position = add_dto.position.unwrap_or(next_position);

    let item = if add_dto.item_type == "playlist" {
        let nested_playlist_id = Uuid::parse_str(&add_dto.item_id).map_err(|_| StatusCode::BAD_REQUEST)?;
        ensure_user_playlist_owner(state.db(), user.id, nested_playlist_id).await?;
        if creates_playlist_cycle(state.db(), playlist_id, nested_playlist_id).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)? {
            return Err(StatusCode::BAD_REQUEST);
        }

        UserPlaylistItemActiveModel {
            playlist_id: Set(playlist_id),
            item_type: Set("playlist".to_string()),
            user_track_id: Set(None),
            nested_playlist_id: Set(Some(nested_playlist_id)),
            position: Set(position),
            ..Default::default()
        }
        .insert(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    } else {
        let source = add_dto.source.ok_or(StatusCode::BAD_REQUEST)?;
        let title = add_dto.title.ok_or(StatusCode::BAD_REQUEST)?;
        let artist = add_dto.artist.ok_or(StatusCode::BAD_REQUEST)?;
        let provider = source.parse::<LibraryProvider>().map_err(|_| StatusCode::BAD_REQUEST)?;
        let user_track = LibrarySyncService::ensure_user_track_from_input(
            state.db(),
            user.id,
            provider,
            &add_dto.item_id,
            &title,
            &artist,
            add_dto.album.as_deref(),
            add_dto.duration,
            add_dto.cover_url.as_deref(),
        )
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        UserPlaylistItemActiveModel {
            playlist_id: Set(playlist_id),
            item_type: Set("track".to_string()),
            user_track_id: Set(Some(user_track.id)),
            nested_playlist_id: Set(None),
            position: Set(position),
            ..Default::default()
        }
        .insert(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    };

    Ok(Json(ApiResponse::success(playlist_item_response(state.db(), item).await?)))
}

pub async fn remove_playlist_item(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path((playlist_id, item_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    ensure_mutable_playlist(state.db(), user.id, playlist_id).await?;

    let item = UserPlaylistItemEntity::find_by_id(item_id)
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .one(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    let removed_position = item.position;
    UserPlaylistItemEntity::delete_by_id(item_id)
        .exec(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let items_to_update = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .filter(UserPlaylistItemColumn::Position.gt(removed_position))
        .all(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for item in items_to_update {
        let mut active = item.into_active_model();
        active.position = Set(active.position.unwrap() - 1);
        active.update(state.db()).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn reorder_playlist_item(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path((playlist_id, item_id)): Path<(Uuid, Uuid)>,
    Json(reorder_dto): Json<ReorderPlaylistItemDto>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    ensure_mutable_playlist(state.db(), user.id, playlist_id).await?;

    let current_item = UserPlaylistItemEntity::find_by_id(item_id)
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .one(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    let old_position = current_item.position;
    let new_position = reorder_dto.new_position;
    if old_position == new_position {
        return Ok(Json(ApiResponse::success(true)));
    }

    let max_position = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .count(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)? as i32 - 1;
    if new_position < 0 || new_position > max_position {
        return Err(StatusCode::BAD_REQUEST);
    }

    let mut moved = current_item.into_active_model();
    moved.position = Set(new_position);
    moved.update(state.db()).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if new_position > old_position {
        let items = UserPlaylistItemEntity::find()
            .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
            .filter(UserPlaylistItemColumn::Position.gt(old_position))
            .filter(UserPlaylistItemColumn::Position.lte(new_position))
            .all(state.db())
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        for item in items {
            if item.id != item_id {
                let mut active = item.into_active_model();
                active.position = Set(active.position.unwrap() - 1);
                active.update(state.db()).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            }
        }
    } else {
        let items = UserPlaylistItemEntity::find()
            .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
            .filter(UserPlaylistItemColumn::Position.gte(new_position))
            .filter(UserPlaylistItemColumn::Position.lt(old_position))
            .all(state.db())
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        for item in items {
            let mut active = item.into_active_model();
            active.position = Set(active.position.unwrap() + 1);
            active.update(state.db()).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        }
    }

    Ok(Json(ApiResponse::success(true)))
}

pub async fn import_canonical_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(canonical_playlist_id): Path<Uuid>,
    Json(payload): Json<ImportCanonicalPlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    let preferred_source = payload
        .preferred_source
        .as_deref()
        .map(str::parse::<LibraryProvider>)
        .transpose()
        .map_err(|_| StatusCode::BAD_REQUEST)?;
    let watched = payload.watched.unwrap_or(true);

    let playlist = LibrarySyncService::import_canonical_playlist(
        state.db(),
        user.id,
        canonical_playlist_id,
        preferred_source,
        watched,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let item_count = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist.id))
        .count(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(ApiResponse::success(
        playlist_model_response(state.db(), playlist, item_count as i32).await?,
    )))
}

pub async fn import_provider_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(payload): Json<ImportProviderPlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, (StatusCode, Json<ApiResponse<()>>)> {
    let provider = payload
        .source
        .parse::<LibraryProvider>()
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error("Unsupported provider".to_string())),
            )
        })?;
    let provider_playlist_id = payload.playlist_id.clone();
    let watched = payload.watched.unwrap_or(true);
    let playlist = LibrarySyncService::import_provider_playlist(
        state.db(),
        user.id,
        provider,
        crate::services::streaming::StreamingPlaylist {
            id: payload.playlist_id,
            name: payload.name,
            description: payload.description,
            owner: payload.owner.unwrap_or_default(),
            source: provider.as_str().to_string(),
            cover_url: payload.cover_url,
            track_count: 0,
            is_public: payload.is_public.unwrap_or(false),
            external_url: None,
        },
        watched,
    )
    .await
    .map_err(|error| {
        error!(
            user_id = %user.id,
            provider = provider.as_str(),
            provider_playlist_id = %provider_playlist_id,
            watched = watched,
            error = %error,
            "Failed to import provider playlist"
        );
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!(
                "Failed to import provider playlist: {}",
                error
            ))),
        )
    })?;

    let item_count = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist.id))
        .count(state.db())
        .await
        .map_err(|error| {
            error!(
                user_id = %user.id,
                playlist_id = %playlist.id,
                provider = provider.as_str(),
                error = %error,
                "Failed to count imported playlist items"
            );
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error(format!(
                    "Failed to count imported playlist items: {}",
                    error
                ))),
            )
        })?;
    let imported_playlist_id = playlist.id;
    Ok(Json(ApiResponse::success(
        playlist_model_response(state.db(), playlist, item_count as i32)
            .await
            .map_err(|error| {
                error!(
                    user_id = %user.id,
                    playlist_id = %imported_playlist_id,
                    provider = provider.as_str(),
                    error = %error,
                    "Failed to build imported playlist response"
                );
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!(
                        "Failed to build imported playlist response: {}",
                        error
                    ))),
                )
            })?,
    )))
}

pub async fn refresh_watched_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, StatusCode> {
    let playlist = LibrarySyncService::refresh_watched_playlist(state.db(), user.id, playlist_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let item_count = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist.id))
        .count(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(ApiResponse::success(
        playlist_model_response(state.db(), playlist, item_count as i32).await?,
    )))
}

async fn ensure_user_playlist_owner(
    db: &sea_orm::DatabaseConnection,
    user_id: Uuid,
    playlist_id: Uuid,
) -> Result<crate::models::UserPlaylistModel, StatusCode> {
    UserPlaylistEntity::find_by_id(playlist_id)
        .filter(UserPlaylistColumn::UserId.eq(user_id))
        .one(db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)
}

async fn ensure_mutable_playlist(
    db: &sea_orm::DatabaseConnection,
    user_id: Uuid,
    playlist_id: Uuid,
) -> Result<crate::models::UserPlaylistModel, StatusCode> {
    let playlist = ensure_user_playlist_owner(db, user_id, playlist_id).await?;
    if playlist.is_read_only {
        return Err(StatusCode::FORBIDDEN);
    }
    Ok(playlist)
}

async fn playlist_item_response(
    db: &sea_orm::DatabaseConnection,
    item: crate::models::UserPlaylistItemModel,
) -> Result<PlaylistItemResponseDto, StatusCode> {
    if item.item_type == "playlist" {
        let nested_id = item.nested_playlist_id.ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
        let nested = UserPlaylistEntity::find_by_id(nested_id)
            .one(db)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
            .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
        Ok(PlaylistItemResponseDto {
            id: item.id,
            item_type: item.item_type,
            item_id: nested_id.to_string(),
            user_track_id: None,
            position: item.position,
            added_at: item.created_at,
            title: None,
            artist: None,
            album: None,
            duration: None,
            source: None,
            cover_url: None,
            is_playlist: true,
            playlist_name: Some(nested.name),
        })
    } else {
        let user_track_id = item.user_track_id.ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
        let track = UserTrackEntity::find_by_id(user_track_id)
            .one(db)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
            .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
        Ok(PlaylistItemResponseDto {
            id: item.id,
            item_type: item.item_type,
            item_id: track.provider_track_id,
            user_track_id: Some(user_track_id),
            position: item.position,
            added_at: item.created_at,
            title: Some(track.title),
            artist: Some(track.artist),
            album: track.album_name,
            duration: track.duration,
            source: Some(track.source),
            cover_url: cache_cover_url(track.cover_url),
            is_playlist: false,
            playlist_name: None,
        })
    }
}

async fn playlist_model_response(
    db: &sea_orm::DatabaseConnection,
    playlist: UserPlaylistModel,
    item_count: i32,
) -> Result<PlaylistResponseDto, StatusCode> {
    let preview_cover_urls = if item_count > 0 {
        playlist_preview_cover_urls(db, playlist.id).await?
    } else {
        Vec::new()
    };

    Ok(PlaylistResponseDto {
        id: playlist.id,
        canonical_playlist_id: playlist.canonical_playlist_id,
        name: playlist.name,
        description: playlist.description,
        source: playlist.source,
        provider_playlist_id: playlist.provider_playlist_id,
        is_public: playlist.is_public,
        is_read_only: playlist.is_read_only,
        is_watched: playlist.is_watched,
        last_synced_at: playlist.last_synced_at,
        created_at: playlist.created_at,
        updated_at: playlist.updated_at,
        item_count,
        preview_cover_urls,
    })
}

async fn playlist_preview_cover_urls(
    db: &sea_orm::DatabaseConnection,
    playlist_id: Uuid,
) -> Result<Vec<String>, StatusCode> {
    let items = UserPlaylistItemEntity::find()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_id))
        .order_by_asc(UserPlaylistItemColumn::Position)
        .limit(16)
        .all(db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let track_ids = items
        .iter()
        .filter_map(|item| item.user_track_id)
        .collect::<Vec<_>>();
    if track_ids.is_empty() {
        return Ok(Vec::new());
    }

    let tracks_by_id = UserTrackEntity::find()
        .filter(UserTrackColumn::Id.is_in(track_ids))
        .all(db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .into_iter()
        .map(|track| (track.id, track))
        .collect::<HashMap<_, _>>();

    let mut preview_cover_urls = Vec::new();
    for item in items {
        let Some(user_track_id) = item.user_track_id else {
            continue;
        };
        let Some(track) = tracks_by_id.get(&user_track_id) else {
            continue;
        };
        let Some(cover_url) = cache_cover_url(track.cover_url.clone()) else {
            continue;
        };
        if preview_cover_urls.contains(&cover_url) {
            continue;
        }

        preview_cover_urls.push(cover_url);
        if preview_cover_urls.len() == 4 {
            break;
        }
    }

    Ok(preview_cover_urls)
}

async fn creates_playlist_cycle(
    db: &sea_orm::DatabaseConnection,
    playlist_id: Uuid,
    nested_playlist_id: Uuid,
) -> Result<bool, sea_orm::DbErr> {
    let mut stack = vec![nested_playlist_id];
    let mut visited = HashSet::new();
    while let Some(current) = stack.pop() {
        if current == playlist_id {
            return Ok(true);
        }
        if !visited.insert(current) {
            continue;
        }
        let nested_items = UserPlaylistItemEntity::find()
            .filter(UserPlaylistItemColumn::PlaylistId.eq(current))
            .filter(UserPlaylistItemColumn::ItemType.eq("playlist"))
            .all(db)
            .await?;
        stack.extend(nested_items.into_iter().filter_map(|item| item.nested_playlist_id));
    }
    Ok(false)
}