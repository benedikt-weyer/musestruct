use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
}; 
use axum_extra::{
    headers::{authorization::Bearer, Authorization},
    TypedHeader,
};
use serde::{Deserialize, Serialize};
use anyhow::Result;
use std::sync::Arc;

use crate::services::AuthService;
use crate::models::{CreateUserDto, LoginDto, UserResponseDto};

#[derive(Clone)]
pub struct AppState {
    pub auth_service: AuthService,
    pub streaming_service: Arc<crate::services::streaming_service::StreamingService>,
}

impl AppState {
    pub fn db(&self) -> &sea_orm::DatabaseConnection {
        &self.auth_service.db
    }
}

#[derive(Serialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub message: Option<String>,
}

impl<T> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            message: None,
        }
    }

    pub fn error(message: String) -> ApiResponse<()> {
        ApiResponse {
            success: false,
            data: None,
            message: Some(message),
        }
    }
}

#[derive(Serialize)]
pub struct LoginResponse {
    pub user: UserResponseDto,
    pub session_token: String,
}

pub async fn register(
    State(state): State<AppState>,
    Json(user_data): Json<CreateUserDto>,
) -> Result<Json<ApiResponse<UserResponseDto>>, (StatusCode, Json<ApiResponse<()>>)> {
    match state.auth_service.register_user(user_data).await {
        Ok(user) => Ok(Json(ApiResponse::success(user))),
        Err(err) => Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()>::error(err.to_string())),
        )),
    }
}

pub async fn login(
    State(state): State<AppState>,
    Json(login_data): Json<LoginDto>,
) -> Result<Json<ApiResponse<LoginResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    match state.auth_service.login_user(login_data).await {
        Ok((user, session_token)) => {
            let response = LoginResponse { user, session_token };
            Ok(Json(ApiResponse::success(response)))
        },
        Err(err) => Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(err.to_string())),
        )),
    }
}

pub async fn logout(
    State(state): State<AppState>,
    TypedHeader(authorization): TypedHeader<Authorization<Bearer>>,
) -> Result<Json<ApiResponse<()>>, (StatusCode, Json<ApiResponse<()>>)> {
    let session_token = authorization.token();
    
    match state.auth_service.logout_user(session_token).await {
        Ok(_) => Ok(Json(ApiResponse::success(()))),
        Err(err) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(err.to_string())),
        )),
    }
}

pub async fn me(
    State(state): State<AppState>,
    TypedHeader(authorization): TypedHeader<Authorization<Bearer>>,
) -> Result<Json<ApiResponse<UserResponseDto>>, (StatusCode, Json<ApiResponse<()>>)> {
    let session_token = authorization.token();
    
    match state.auth_service.validate_session(session_token).await {
        Ok(user) => Ok(Json(ApiResponse::success(user))),
        Err(err) => Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(err.to_string())),
        )),
    }
}

// Middleware to extract authenticated user
pub async fn auth_middleware(
    State(state): State<AppState>,
    mut req: axum::extract::Request,
    next: axum::middleware::Next,
) -> Result<axum::response::Response, (StatusCode, Json<ApiResponse<()>>)> {
    let auth_header = req.headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|header| header.to_str().ok())
        .and_then(|header| {
            if header.starts_with("Bearer ") {
                Some(&header[7..])
            } else {
                None
            }
        });

    if let Some(session_token) = auth_header {
        match state.auth_service.validate_session(session_token).await {
            Ok(user) => {
                req.extensions_mut().insert(user);
                Ok(next.run(req).await)
            },
            Err(_) => Err((
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse::<()>::error("Invalid or expired session".to_string())),
            )),
        }
    } else {
        Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error("Authorization header required".to_string())),
        ))
    }
}
