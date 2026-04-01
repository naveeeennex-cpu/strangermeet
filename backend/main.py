from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import create_pool, close_pool, get_db, seed_demo_data
from routers import auth, users, posts, events, chat, stories, friends, communities, reels, admin, upload, bookings


@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_pool()
    app.state.pool = get_db()
    await seed_demo_data()
    yield
    await close_pool()


app = FastAPI(
    title="StrangerMeet API",
    description="Backend API for StrangerMeet - A Social Meetup App",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS - allow all origins for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(posts.router)
app.include_router(events.router)
app.include_router(chat.router)
app.include_router(stories.router)
app.include_router(friends.router)
app.include_router(communities.router)
app.include_router(reels.router)
app.include_router(admin.router)
app.include_router(upload.router)
app.include_router(bookings.router)


@app.get("/")
async def root():
    return {"app": "StrangerMeet API", "version": "1.0.0"}
