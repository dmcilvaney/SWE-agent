#!/usr/bin/env python3

import asyncio
import os
import sys
from pprint import pprint
import argparse
import json
from typing import List, Optional

from pydantic import BaseModel, Field
from browser_use import Agent, Browser, BrowserConfig, Controller, ActionResult
from langchain_openai import AzureChatOpenAI

# Set the model here:
_MODEL = "gpt-4o"  
_MODEL = "o3-mini"

_FORCE_HEADLESS = True
_FORCE_NO_VISION = False

use_headless = _FORCE_HEADLESS
use_vision = not _FORCE_NO_VISION

# Only gpt-4o supports vision
if _MODEL != "gpt-4o":
    use_vision = False

# Use our proxy endpoint instead of direct Azure endpoint
api_key = "sk-proxy-fake-key-for-local-use-only"
proxy_endpoint = "http://127.0.0.1:8000"  # Local proxy server

llm = AzureChatOpenAI(
    model = _MODEL,
    api_version = '2024-12-01-preview',
    api_key = api_key,
    azure_endpoint = proxy_endpoint,
    azure_deployment = _MODEL,
    disabled_params={'parallel_tool_calls': None},
)

browser_config = BrowserConfig(
    headless = use_headless,
)
browser = Browser(config = browser_config)

# Define a Pydantic model for structured CVE data
class CVEInformation(BaseModel):
    id: str = Field(description="The CVE identifier (e.g., CVE-2022-1234)")
    description: str = Field(description="Detailed description of the vulnerability")
    patches: Optional[List[str]] = Field(default=None, description="List of patches or fixes available for the CVE")

class ResearchResult(BaseModel):
    url: str = Field(description="The URL that was researched")
    content: str = Field(description="The content extracted from the URL")
    patches: Optional[List[str]] = Field(default=None, description="List of patches or fixes found during research")
   
# Make a nested async function to handle the research
async def research_internal(cve:str, urls: List[str]) -> str:
    """Research multiple URLs and combine the information found."""
    combined_results = []
    
    for url in urls:
        research_prompt = f"""
Researcher. Explore links provided by a main agent, and return any relevant information you find.
STEP 1:
    Visit the requested link: {url}

STEP 2: 
    Gather any information that would be useful for an enginner to fix {cve}:
        - Keep an eye out for patches or commits that may fix the cve.
            - If there is a patch link, try to find a raw patch file instead (ie add '.patch' to the end of a github link, or otherwise look for a 'raw' link). Unsure the links works, and keep track of these URLs for later.
        - Use your best judgement to determine if any recursive links contained in those references might contain additional relevant info. Vist them if so.


STEP 3:
    Return the information you found, including any useful links to patches or commits.
"""

        async with await browser.new_context() as context:
            # Create a controller with our output model
            controller = Controller(output_model=ResearchResult)

            # Create a new agent for the research task
            research_agent = Agent(
                browser_context=context,
                task=research_prompt,
                llm=llm,
                use_vision=use_vision,
                initial_actions=[
                    {'open_tab': {'url': url}}
                ],
                controller=controller,  # Use the controller with our output model
            )
            
            # Run the research agent and return the result
            history = await research_agent.run()
            combined_results.append(f"Results from {url}:\n{history.final_result()}")
    
    # Combine all results
    return ActionResult(extracted_content="\n\n".join(combined_results))

async def get_cve_description(cve_id):
    """Get the description of a CVE from the NIST NVD database using structured output."""
    url = f"https://nvd.nist.gov/vuln/detail/{cve_id}"
    main_prompt = f"""        
STEP 1:
    Visit {url}.

STEP 2:
    Look for additional data in the 'References to Advisories, Solutions, and Tools' section.
        - Use the research tool to investigate relevant links you find.
        - Keep track of any patches or commits the research tool finds.

STEP 3:
    Combine the information from the research results, and any details from the original page, into an in-depth description of the CVE for
        an engineer. Do not include extraneous details that don't pertain to the CVE.
        - The final output should be a JSON object with the following fields: id, description.
        - Add newlines into the description as needed to make it readable on a cmndline terminal (~120 characters)
        - If any relevant patch links were found, include them in the 'patches' field of the JSON object.
            - If there are two otherwise identical links, but one is a raw patch file, prefer the raw patch file.
"""


    async with await browser.new_context() as context:

        # Create a controller with our output model
        controller = Controller(output_model=CVEInformation)

        @controller.action('Research up to 10 urls. Call additional times for more.')
        async def research_link(link1: str, link2: str, link3: str, link4: str, link5: str,
                                link6: str, link7: str, link8: str, link9: str, link10: str) -> ActionResult:
            """Research multiple links and return combined information."""
            links = [link for link in [link1, link2, link3, link4, link5, link6, link7, link8, link9, link10] if link]

            return await research_internal(cve_id, links)

        main_agent = Agent(
            browser_context=context,
            task = main_prompt,
            llm = llm,
            use_vision=use_vision,
            controller=controller,  # Use the controller with our output model
            initial_actions=[
                {'open_tab': {'url': url}}
            ],
        )

        try:
            history = await main_agent.run()
            result = history.final_result()
            
            # Parse the result to validate it against our schema
            if result:
                validated_result = CVEInformation.model_validate_json(result)
                return validated_result.model_dump()
            else:
                return {"error": "No result returned from agent", "partial_result": "Failed to retrieve CVE information"}
        except Exception as e:
            print(f"Error getting CVE description: {e}")
            return {"error": str(e), "partial_result": "Failed to retrieve CVE information"}

def save_cve_summary(cve_info, output_file):
    """Save the CVE summary to a file."""
    with open(output_file, 'w') as f:
        # If we got an error, write that instead
        if 'error' in cve_info:
            f.write(f"Error retrieving CVE information: {cve_info['error']}\n")
            if 'partial_result' in cve_info:
                f.write(f"Partial information: {cve_info['partial_result']}\n")
            return
        
        # Format the CVE information
        f.write(f"CVE ID: {cve_info.get('id', 'Unknown')}\n\n")
        f.write(f"Description: {cve_info.get('description', 'No description available')}\n\n")

        if cve_info.get('patches'):
            f.write("Patches:\n")
            for patch in cve_info['patches']:
                f.write(f"- {patch}\n")

    with open(f"{output_file}.json", 'w') as f:
        # Save the raw JSON output
        json.dump(cve_info, f, indent=4)
        print(f"Saved CVE information to {output_file} and {output_file}.json")

async def main():
    parser = argparse.ArgumentParser(description='Get CVE information from NIST NVD')
    parser.add_argument('cve_id', help='The CVE ID to lookup (e.g., CVE-2022-2022)')
    parser.add_argument('output_file', help='Path to save the CVE summary')
    
    args = parser.parse_args()
    
    print(f"Looking up information for {args.cve_id}...")
    cve_info = await get_cve_description(args.cve_id)
    
    print(f"Saving information to {args.output_file}")
    save_cve_summary(cve_info, args.output_file)
    
    print("Done!")

if __name__ == "__main__":
    sys.exit(asyncio.run(main()))