# This Python script was modified from https://github.com/oats-center/tb-exporter, commit 4813d00.
# All credits to them for fetch.py!

import sys
import os
import argparse
import requests
import pandas as pd
import pathlib
from datetime import datetime, timezone

def login(url, username, password):
    # Log into ThingsBoard
    return requests.post(f"{url}/api/auth/login", json={
        "username": username,
        "password": password
    }).json()['token']

def get_keys(url, token, device):
    return requests.get(f"{url}/api/plugins/telemetry/DEVICE/{device}/keys/timeseries",
                 headers={
                     'content-type': 'application/json',
                     'x-authorization': f"bearer {token}"
                 }).json()

def get_data_chunk(url, token, device, key, start, stop, limit):
    return requests.get(f"{url}/api/plugins/telemetry/DEVICE/{device}/values/timeseries",
             headers={
                 'content-type': 'application/json',
                 'x-authorization': f"bearer {token}"
             },
            params= {
                'keys': key,
                'startTs': start,
                'endTs': stop,
                'limit': limit,
                'agg': 'NONE'
            }).json()

def get_data(url, token, device, key, start, stop):
    p = pd.DataFrame()

    # You have to request data backwards in time ...
    while start < stop:
        data = get_data_chunk(url, token, device, key, start, stop, 10000)

        if key not in data:
            break;

        t = pd.DataFrame.from_records(data[key])
        t.set_index('ts', inplace=True)
        t.rename(columns={'value': key}, inplace=True)
        p = p._append(t)

        # Update "new" stop time
        stop = data[key][-1]['ts'] - 1

    return p

parser = argparse.ArgumentParser(description="Fetch DEVICE data from ThingsBoard")
parser.add_argument('url', type=str, help='Base URL to ThingsBoard API')
parser.add_argument('--username', '-u', type=str, required=True, help='ThingsBoard username')
parser.add_argument('--password', '-p', type=str, required=True, help='ThingsBoard password')
parser.add_argument('--device', '-d', type=str, required=True, action='append', help='ThingsBoard device id to fetch data of')
parser.add_argument('--key', '-k', type=str, action='append', help='ThingsBoard device key to fetch')
parser.add_argument('--start', type=int, default=0, help='Start time as milisecond UNIX timestamp')
parser.add_argument('--stop', type=int, default=sys.maxsize, help='Stop time as milisecond UNIX timestamp')
parser.add_argument('--label', type=str, required=True, help='Label name used in filename')
parser.add_argument('--tag', type=str, required=True, help='Tag name used as subdirectory')
parser.add_argument('--output', type=str, default='data', help='Output data folder')

args = parser.parse_args()

token = login(args.url, args.username, args.password)

# Set the fixed width for wrapping
max_width = 120

# fetch data
for device in args.device:
    keys = args.key if args.key else get_keys(args.url, token, device)

    # Initialize DataFrame for device data
    p = pd.DataFrame()

    # Check if any keys were found
    if not keys:
        print(f"    No data available.", end="")
    else:
        # Start printing the keys with the initial indentation
        print(f"    ", end="", flush=True)

        # To wrap the keys line
        current_line_length = 4  # start with initial indentation (4 spaces)

        # Iterate over keys and fetch data
        for i, key in enumerate(keys):
            # Prepare the key string and comma handling
            key_str = f"{key}"
            is_last_key = i == len(keys) - 1
            comma = "," if not is_last_key else ""  # Add a comma unless it's the last key
            key_length = len(key_str) + len(comma)

            # If the current line plus the next key exceeds max width, print a newline before the key
            if current_line_length + key_length > max_width:
                print()  # move to a new line
                print("    ", end="", flush=True)  # re-indent
                current_line_length = 4  # reset line length for the new line

            # Print the key followed by the comma (if not the last key)
            print(f"{key_str}{comma} ", end="", flush=True)
            current_line_length += key_length + 1  # account for the key, comma, and space

            # Fetch data for the key
            p = pd.concat([p, get_data(args.url, token, device, key, args.start, args.stop)], axis=1)

    # Add a new column for the UTC timestamp
    if not p.empty:
        p.insert(0, 'utc', pd.to_datetime(p.index, unit='ms', utc=True).strftime('%Y-%m-%d %H:%M:%S'))
    
    # Ensure a directory exists to save the file
    pathlib.Path(f"{args.output}/{args.tag}").mkdir(parents=True, exist_ok=True)
    
    # Save the dataFrame to a CSV file
    output_file = f"{args.output}/{args.tag}/{args.label}-{device}.csv"
    p.to_csv(output_file)

    # Get the number of rows in the CSV file
    row_count = len(p)

    # Show last seen datetime
    if row_count > 1:
        now = datetime.now(timezone.utc)  # Get current time as a datetime object
        last_seen_time = datetime.strptime(p['utc'].values[0], '%Y-%m-%d %H:%M:%S').replace(tzinfo=timezone.utc)
        # Calculate the time difference in hours
        difference = now - last_seen_time
        hours, remainder = divmod(difference.total_seconds(), 3600)
        minutes = remainder // 60
        lastseen = f"{p['utc'].values[0]} UTC, {int(hours)}h {int(minutes)}m ago."
        
        # Print the result
        print(f"\n    \033[32mDone: pulled {row_count} rows.\033[0m \033[33mLast seen: {lastseen}\033[0m")
    else:
        print(f"\n    \033[32mDone: pulled 0 rows.\033[0m")
