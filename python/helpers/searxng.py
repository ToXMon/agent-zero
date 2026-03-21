import asyncio
import aiohttp
from python.helpers import runtime

URL = "http://localhost:55510/search"
# PATCH: Add explicit timeout to prevent indefinite hangs that block the event loop
SEARCH_TIMEOUT = aiohttp.ClientTimeout(total=30, connect=10)

async def search(query:str):
    return await runtime.call_development_function(_search, query=query)

async def _search(query:str):
    try:
        async with aiohttp.ClientSession(timeout=SEARCH_TIMEOUT) as session:
            async with session.post(URL, data={"q": query, "format": "json"}) as response:
                return await response.json()
    except asyncio.TimeoutError:
        return {"results": [], "error": "Search timed out after 30s"}
