#!/usr/bin/env python3.11

import os
import sys
from pprint import pprint
import requests
import json

def main():
    # Use our proxy endpoint instead of direct Azure endpoint
    api_key = "sk-proxy-fake-key-for-local-use-only"
    proxy_endpoint = "http://127.0.0.1:8000"  # Local proxy server

    # Test the proxy server's health endpoint
    try:
        health_response = requests.get(f"{proxy_endpoint}/health")
        print("Health check status:", health_response.status_code)
        print("Health check response:", health_response.json())
    except Exception as e:
        print(f"Health check failed: {e}")
        return

    # Test chat completions via the proxy
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }

    data = {
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "What is Azure OpenAI?"}
        ],
        # No model field needed - deployment is specified in the URL
    }

    # Azure OpenAI requires an api-version parameter
    params = {
        "api-version": "2024-12-01-preview"
    }

    deployment = "o3-mini"  # The deployment to use

    try:
        print("\nSending request to proxy...")
        response = requests.post(
            f"{proxy_endpoint}/openai/deployments/{deployment}/chat/completions",
            headers=headers,
            json=data,
            params=params
        )

        print(f"Response status: {response.status_code}")

        if response.status_code == 200:
            result = response.json()
            content = result["choices"][0]["message"]["content"]
            print("\nResponse from proxy server:")
            print("-" * 50)
            print(content)
            print("-" * 50)
        else:
            print("Error response:", response.text)
    except Exception as e:
        print(f"Request failed: {e}")

if __name__ == "__main__":
    main()
