import sys
import os
import argparse
import requests
import pandas as pd
import pathlib
from datetime import datetime

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
parser.add_argument('--label', type=str, required=True, help='Label name used in filename')
parser.add_argument('--project', type=str, required=True, help='Project name used as subdirectory')
parser.add_argument('--start', type=int, default=0, help='Start time as milisecond UNIX timestamp')
parser.add_argument('--stop', type=int, default=sys.maxsize, help='Stop time as milisecond UNIX timestamp')

args = parser.parse_args()

token = login(args.url, args.username, args.password)

# fetch data
for device in args.device:
    keys = args.key if args.key else get_keys(args.url, token, device)

    # Initialize DataFrame for device data
    p = pd.DataFrame()

    # Start printing the keys on the same line
    print(f"    ", end="", flush=True)

    # Iterate over keys and fetch data
    for i, key in enumerate(keys):
        if i > 0:
            print(f", \033[33m{key}\033[0m", end="", flush=True)
        else:
            print(f"\033[33m{key}\033[0m", end="", flush=True)

        p = pd.concat([p, get_data(args.url, token, device, key, args.start, args.stop)], axis=1)

    # Ensure a directory exists to save the file
    pathlib.Path(f"./data/{args.project}").mkdir(parents=True, exist_ok=True)
    
    # Save the DataFrame to a CSV file
    output_file = f"./data/{args.project}/{args.label}-{device}.csv"
    p.to_csv(output_file)

    # Get the number of rows in the CSV file
    row_count = len(p)

    # Convert the value at row 2, column 1 (assuming index 'ts' is the first column)
    if row_count > 1:
        timestamp = p.index[1]  # row 2 (index starts from 0)
        converted_time = datetime.utcfromtimestamp(timestamp / 1000).strftime('%Y-%m-%d %H:%M:%S')
        print(f"\n    \033[32mDone: pulled {row_count} lines.\033[0m Last device connection: {converted_time}")
