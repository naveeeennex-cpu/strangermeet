from fastapi import APIRouter, HTTPException, status, Request

from schemas.user import UserSignup, UserLogin, Token
from services.auth import hash_password, verify_password, create_access_token

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/signup", response_model=Token, status_code=status.HTTP_201_CREATED)
async def signup(user_data: UserSignup, request: Request):
    pool = request.app.state.pool

    # Check if email already exists
    existing = await pool.fetchrow("SELECT id FROM users WHERE email = $1", user_data.email)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    # Check if username already exists
    username = user_data.username.lower()
    existing_username = await pool.fetchrow("SELECT id FROM users WHERE username = $1", username)
    if existing_username:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already taken",
        )

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO users (name, email, password_hash, username, phone, interests, role, bio, occupation, college_name, company_name, designation)
            VALUES ($1, $2, $3, $4, $5, $6, $7, '', $8, $9, $10, $11)
            RETURNING id, role
            """,
            user_data.name,
            user_data.email,
            hash_password(user_data.password),
            username,
            user_data.phone,
            user_data.interests,
            user_data.role,
            user_data.occupation,
            user_data.college_name,
            user_data.company_name,
            user_data.designation,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create user: {str(e)}",
        )

    user_id = str(row["id"])
    access_token = create_access_token(data={"sub": user_id})
    return Token(access_token=access_token, role=row["role"])


@router.post("/login", response_model=Token)
async def login(user_data: UserLogin, request: Request):
    pool = request.app.state.pool

    user = await pool.fetchrow("SELECT * FROM users WHERE email = $1", user_data.email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not verify_password(user_data.password, user["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    user_id = str(user["id"])
    access_token = create_access_token(data={"sub": user_id})
    return Token(access_token=access_token, role=user.get("role", "customer"))


@router.get("/check-username/{username}")
async def check_username(username: str, request: Request):
    pool = request.app.state.pool
    existing = await pool.fetchrow("SELECT id FROM users WHERE username = $1", username.lower())
    return {"available": existing is None}
