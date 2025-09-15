use anyhow::{Result, anyhow};
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{rand_core::OsRng, SaltString};
use rand::Rng;
use sea_orm::{DatabaseConnection, EntityTrait, Set, ActiveModelTrait, ColumnTrait, QueryFilter, ActiveModelBehavior};
use uuid::Uuid;
use chrono::{Utc, Duration, NaiveDateTime};
use base64::{Engine, engine::general_purpose};

use crate::models::{UserEntity, UserSessionEntity, UserResponseDto, CreateUserDto, LoginDto, UserActiveModel, UserSessionActiveModel};

#[derive(Clone)]
pub struct AuthService {
    db: DatabaseConnection,
    session_duration: Duration,
}

impl AuthService {
    pub fn new(db: DatabaseConnection) -> Self {
        Self {
            db,
            session_duration: Duration::days(7), // 7 days default
        }
    }

    pub async fn register_user(&self, user_data: CreateUserDto) -> Result<UserResponseDto> {
        // Check if user already exists
        let existing_user = UserEntity::find()
            .filter(crate::models::UserColumn::Email.eq(&user_data.email))
            .one(&self.db)
            .await?;

        if existing_user.is_some() {
            return Err(anyhow!("User with this email already exists"));
        }

        // Hash password
        let password_hash = self.hash_password(&user_data.password)?;

        // Create user
        let user = UserActiveModel {
            email: Set(user_data.email),
            username: Set(user_data.username),
            password_hash: Set(password_hash),
            ..UserActiveModel::new()
        };

        let user = user.insert(&self.db).await?;
        Ok(UserResponseDto::from(user))
    }

    pub async fn login_user(&self, login_data: LoginDto) -> Result<(UserResponseDto, String)> {
        // Find user by email
        let user = UserEntity::find()
            .filter(crate::models::UserColumn::Email.eq(&login_data.email))
            .one(&self.db)
            .await?
            .ok_or_else(|| anyhow!("Invalid email or password"))?;

        // Verify password
        if !self.verify_password(&login_data.password, &user.password_hash)? {
            return Err(anyhow!("Invalid email or password"));
        }

        // Create session
        let session_token = self.generate_session_token();
        let session = UserSessionActiveModel {
            user_id: Set(user.id),
            session_token: Set(session_token.clone()),
            expires_at: Set((Utc::now() + self.session_duration).naive_utc()),
            ..UserSessionActiveModel::new()
        };

        session.insert(&self.db).await?;

        Ok((UserResponseDto::from(user), session_token))
    }

    pub async fn validate_session(&self, session_token: &str) -> Result<UserResponseDto> {
        let session = UserSessionEntity::find()
            .filter(crate::models::UserSessionColumn::SessionToken.eq(session_token))
            .filter(crate::models::UserSessionColumn::IsActive.eq(true))
            .filter(crate::models::UserSessionColumn::ExpiresAt.gt(Utc::now().naive_utc()))
            .one(&self.db)
            .await?
            .ok_or_else(|| anyhow!("Invalid or expired session"))?;

        let user = UserEntity::find_by_id(session.user_id)
            .one(&self.db)
            .await?
            .ok_or_else(|| anyhow!("User not found"))?;

        Ok(UserResponseDto::from(user))
    }

    pub async fn logout_user(&self, session_token: &str) -> Result<()> {
        let session = UserSessionEntity::find()
            .filter(crate::models::UserSessionColumn::SessionToken.eq(session_token))
            .one(&self.db)
            .await?;

        if let Some(session) = session {
            let mut session: UserSessionActiveModel = session.into();
            session.is_active = Set(false);
            session.update(&self.db).await?;
        }

        Ok(())
    }

    pub async fn cleanup_expired_sessions(&self) -> Result<()> {
        use sea_orm::QueryTrait;
        
        let expired_sessions = UserSessionEntity::find()
            .filter(crate::models::UserSessionColumn::ExpiresAt.lt(Utc::now().naive_utc()))
            .all(&self.db)
            .await?;

        for session in expired_sessions {
            let mut session: UserSessionActiveModel = session.into();
            session.is_active = Set(false);
            session.update(&self.db).await?;
        }

        Ok(())
    }

    fn hash_password(&self, password: &str) -> Result<String> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();
        let password_hash = argon2.hash_password(password.as_bytes(), &salt)
            .map_err(|e| anyhow!("Failed to hash password: {}", e))?;
        Ok(password_hash.to_string())
    }

    fn verify_password(&self, password: &str, hash: &str) -> Result<bool> {
        let parsed_hash = PasswordHash::new(hash)
            .map_err(|e| anyhow!("Failed to parse password hash: {}", e))?;
        let argon2 = Argon2::default();
        Ok(argon2.verify_password(password.as_bytes(), &parsed_hash).is_ok())
    }

    fn generate_session_token(&self) -> String {
        let mut rng = rand::rng();
        let token: [u8; 32] = rng.random();
        general_purpose::STANDARD.encode(token)
    }
}
