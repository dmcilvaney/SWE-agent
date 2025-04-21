#!/usr/bin/env python3.11

import asyncio
import os
import sys
from pprint import pprint
from typing import List

from browser_use import Agent, AgentHistoryList, Browser, BrowserConfig
from langchain_openai import AzureChatOpenAI

async def main():
    what_to_browse = "What is the fax number of example.com's maintainer?"  # Default URL

    # Use our proxy endpoint instead of direct Azure endpoint
    api_key = "sk-proxy-fake-key-for-local-use-only"
    proxy_endpoint = "http://127.0.0.1:8000"  # Local proxy server

    llm = AzureChatOpenAI(
        model = "o3-mini",
        api_version = '2024-12-01-preview',  # Updated to match the proxy's default API version
        api_key = api_key,
        azure_endpoint = proxy_endpoint,
        azure_deployment = "o3-mini",  # Match the deployment from proxy
        disabled_params={'parallel_tool_calls': None},
    )

    browser_config = BrowserConfig(
        headless = False
    )
    browser = Browser(config = browser_config)

    agent = Agent(
        browser = browser,
        task = what_to_browse,
        llm = llm,
        use_vision=False,
    )

    history : AgentHistoryList = await agent.run()
    print("Final Result:")
    pprint(history.final_result(), indent=4)


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
