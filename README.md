## `tbatch`: remotely run batch operations on your Thingsboard devices

The free Thingsboard plan (Community Edition) does not make it easy to download full datasets remotely, nor does it provide user-friendly tools to manipulate device attributes in batch to change the behaviour of multiple devices at once. To work around these limitations, `tbatch` allows programmatically downloading data or editing attributes:

```
Interact with the ThingsBoard API for managing telemetry attributes and fetching data in batch.

Usage: ./tbatch [options]

Options:
  -d, --domain DOMAIN      ThingsBoard URL domain
  -e, --email EMAIL        Login email
  -p, --password PASSWORD  Password
  -f, --file FILE          CSV file listing device information (default: deviceids.csv)
  -a, --action ACTION      Action: post/delete/get (attributes), fetch (data), or inventory (build device CSV list) (default: get)
  -t, --tags TAG(S)        Target device tag(s) (comma-separated, or "*")
  -l, --labels LABEL(S)    Target device label(s) (comma-separated, or "*")
  -s, --scope SCOPE        Scope of the target attribute: server or shared (default: shared)
  -k, --key KEY            Target attribute key name (for post/delete actions)
  -v, --value VALUE        New value for target attribute (for post action)
  -o, --output FOLDER      Output folder for fetched data (default: ./data/)
  -c, --config FILE        Use custom config file
  -q, --quit               Run once then quit instead of prompting for new actions (only place this flag at the end of the command)
  -h, --help               Show this help and exit
```

## Demonstration

`placeholder` for Asciinema casts to be added later.

## Usage

This script supports running actions on subsets of devices without independently from the Thingsboard frontend: just add tags to devices in the CSV file that lists `Device IDs` (which can be generated with `./tbatch --action inventory`) and then use target tags in the script. Below is an example showing interactive mode to fetch raw data from all devices with the `demo` tag:

```
$ ./tbatch
- Enter your Thingsboard URL: iot.pclim.net
- Enter your login email: tenant@inrae.fr
- Enter your password: 
- Enter action to perform: post/delete/get (attributes), fetch (data) or inventory (build device CSV list): fetch
- List tag(s) of the target devices (comma-separated, or leave blank): demo
- List labels of the target devices (comma-separated, or leave blank): 
  FG100 (527dc420-71e8-11ef-9698-4f87e1c8862d) [DEMO] - Fetching to data/…
    temperature, battery, rssi, acq_duration, size_csv, size_data, humidity, lux, ntc0_temp, ntc1_temp, ntc2_temp, 
    ntc3_temp, wkp, vct, ver, ana0, ana1, ana2, ana3 
    Done: pulled 518 rows. Last seen: 2024-09-21 13:11:42 UTC, 43h 49m ago.
  FG101 (3ee18310-75bd-11ef-9698-4f87e1c8862d) [DEMO] - Fetching to data/…
    temperature, battery, rssi, acq_duration, size_csv, size_data, humidity, lux, ntc0_temp, ntc1_temp, ntc2_temp, 
    ntc3_temp, wkp, vct, ver 
    Done: pulled 435 rows. Last seen: 2024-09-23 08:36:07 UTC, 0h 25m ago.
  FG102 (3ee15c00-75bd-11ef-9698-4f87e1c8862d) [DEMO] - Fetching to data/…
    temperature, battery, rssi, acq_duration, size_csv, size_data, humidity, lux, ntc0_temp, ntc1_temp, ntc2_temp, 
    ntc3_temp, wkp, vct, ver 
    Done: pulled 5 rows. Last seen: 2024-09-21 13:01:05 UTC, 44h 0m ago.
  FG103 (3ee1f840-75bd-11ef-9698-4f87e1c8862d) [DEMO] - Fetching to data/…
    temperature, battery, rssi, acq_duration, size_csv, size_data, humidity, lux, ntc0_temp, ntc1_temp, ntc2_temp, 
    ntc3_temp, wkp, vct, ver 
    Done: pulled 57 rows. Last seen: 2024-09-23 08:20:04 UTC, 0h 41m ago.
  FG104 (3ee29482-75bd-11ef-9698-4f87e1c8862d) [DEMO] - Fetching to data/…
    temperature, battery, rssi, acq_duration, size_csv, size_data, humidity, lux, ntc0_temp, ntc1_temp, ntc2_temp, 
    ntc3_temp, wkp, vct, ver 
    Done: pulled 63 rows. Last seen: 2024-09-23 08:08:58 UTC, 0h 52m ago.
  FG105 (3ee357d1-75bd-11ef-9698-4f87e1c8862d) [DEMO] - Fetching to data/…
    No data available.
    Done: pulled 0 rows.
```

``` sh
$ tree data
data/
└── DEMO
    ├── FG100-527dc420-71e8-11ef-9698-4f87e1c8862d.csv
    ├── FG101-3ee18310-75bd-11ef-9698-4f87e1c8862d.csv
    ├── FG102-3ee15c00-75bd-11ef-9698-4f87e1c8862d.csv
    ├── FG103-3ee1f840-75bd-11ef-9698-4f87e1c8862d.csv
    ├── FG104-3ee29482-75bd-11ef-9698-4f87e1c8862d.csv
    └── FG105-3ee357d1-75bd-11ef-9698-4f87e1c8862d.csv

2 directories, 6 files
```

The script can also be run fully non-interactively using runtime flags to automate its execution in a cronjob or other routine.
