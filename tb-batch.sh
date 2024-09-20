#!/usr/bin/env bash

# Script to interact with the ThingsBoard API for managing telemetry attributes and fetching data.

# Help message
show_help() {
    echo "Interact with the ThingsBoard API for managing telemetry attributes and fetching data in batch."
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --domain     ThingsBoard URL domain"
    echo "  -e, --email      Login email"
    echo "  -pw, --password  Password"
    echo "  -f, --file       CSV file listing device information (default: deviceids.csv)"
    echo "  -a, --action     Action: post/delete/get (attributes), fetch (data), or inventory (build device csvlist) (default: get)"
    echo "  -s, --scope      Scope of the attributes: server or shared (default: shared)"
    echo "  -p, --projects   Target project(s) (comma-separated)"
    echo "  -l, --labels     Target device label(s) (comma-separated)"
    echo "  -c, --config     Use custom config file"
    echo "  -o, --once       Run the script once and quit"
    echo "  -h, --help       Display this help and exit"
    echo ""
    echo "Dependencies: curl, jq, python3, python3-pandas"
}

# Check dependencies
check_dependencies() {
    local dependencies=("curl" "jq" "python3")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "\033[31mError: $dep is not installed.\033[0m"
            exit 1
        fi
    done
}

# Check dependencies
check_dependencies

# Read CLI flags
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--domain) domain="$2"; shift ;;
        -e|--email) login_email="$2"; shift ;;
        -pw|--password) password="$2"; shift ;;
        -f|--file) csv_file="$2"; shift ;;
        -a|--action) action="$2"; shift ;;
        -s|--scope) scope="$2"; shift ;;
        -p|--projects) project_selection="$2"; shift ;;
        -l|--labels) label_selection="$2"; shift ;;
	-o|--once) once="true"; shift ;;
	-c|--config) config_file="$2"; shift ;;
	-h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

# Read config file, if any
config_file=${config_file:-tb-batch.conf}

# Check if the configuration file exists
if [[ ! -f "$config_file" ]]; then
    read -p $'\033[34mConfiguration file not found. Generate configuration template? (Y/n): \033[0m' config_reply
    if ! [[ "$config_reply" == "n" ]]; then
	cat > "$config_file" <<EOL
domain=""
login_email=""
csv_file=""
action=""
scope=""
projects=""
labels=""
customerid=""
EOL
    fi
fi

# Source the config file and prefix variables with "def"
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    if [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]]; then
        continue
    fi

    # Remove leading and trailing spaces from the key and value
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    # Prepend "def" to the variable name
    defvar="def${key}"

    # Only set the variable if the value is not empty
    if [[ -n "$value" ]]; then
        eval "$defvar='$value'"
    fi
done < "$config_file"

# Check if csv_file was set at run time, else read from config.file, and if empty, replace by default value
if [[ -z "$csv_file" ]]; then
    csv_file=${defcsv_file:-deviceids.csv}
fi

# Credentials prompts
if [[ -z "$domain" ]]; then
    read -e -p $'\033[34m- Enter your Thingsboard URL:\033[0m ' ${defdomain:+-i "$defdomain"} domain
fi
domain="${domain#https://}"

if [[ -z "$login_email" ]]; then
    read -e -p $'\033[34m- Enter your login email:\033[0m ' ${deflogin_email:+-i "$deflogin_email"} login_email
fi
if [[ -z "$password" ]]; then
    read -s -p $'\033[34m- Enter your password:\033[0m ' password
    echo
fi

# Get an authentication token using login credentials
AUTH_TOKEN=$(curl -s -X POST "https://${domain}:443/api/auth/login" \
  -H "accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${login_email}\", \"password\":\"${password}\"}" | jq -r .token)

# Check if AUTH_TOKEN is null or empty, meaning login failed
if [[ -z "$AUTH_TOKEN" || "$AUTH_TOKEN" == "null" ]]; then
  echo -e "\033[31mError: Failed to authenticate. Please check your credentials.\033[0m"
  exit 1
fi

# Function to handle the "inventory" action
perform_inventory_action() {
  # If file exists, prompt for confirmation
  if [[ -f "$csv_file" ]]; then
      read -p "'$csv_file' already exists. Overwrite it? (y/N): " confirm
      if [[ "$confirm" != "y" ]]; then
          echo "Aborting."
          exit 0
      fi
  fi
  # Perform the GET request to retrieve the inventory of devices
  read -e -p $'\033[34m- Enter your customer ID:\033[0m ' ${defcustomerid:+-i "$defcustomerid"} userid
  response=$(curl -s -X GET \
      "https://${domain}:443/api/customer/${userid}/devices?pageSize=100&page=0&textSearch=FG&sortProperty=label&sortOrder=ASC" \
      -H "accept: application/json" \
      -H "X-Authorization: Bearer ${AUTH_TOKEN}")
  # Check if the response contains an error
  if [[ -z "$response" || "$response" == "null" ]]; then
      echo -e "\033[31mFailed to retrieve devices. Please check that you used a valid customer ID, not a customer name.\033[0m"
      exit 1
  fi
  # Extract device information and save to the CSV file
  echo "deviceid,name,label,project" > "$csv_file"
  echo "$response" | jq -r '.data[] | "\(.id.id),\(.name),\(.label),default"' >> "$csv_file"
  echo -e "\033[32mDevice inventory saved to $csv_file.\033[0m"
}


# Function to process the device updates
interact() {
  # Read and prompt for the action (post, delete, get, fetch or inventory)
  if [[ -z "$action" ]]; then
    read -e -p $'\033[34m- Enter action to perform: post/delete/get (attributes), fetch (data) or inventory (build device CSV list):\033[0m ' ${defaction:+-i "$defaction"} action
  fi
  action=${action:-get}

  # If action is 'inventory' perform the inventory action
  if [[ "$action" == "inventory" || "$action" == "i" ]]; then
    perform_inventory_action
  fi
    
  # Check if the CSV file exists
  if [[ ! -f "$csv_file" ]]; then
      echo -e "\033[31mError: CSV file '$csv_file' not found.\033[0m"
      exit 1
  fi

  # Prompt to select projects (if blank, all will be used)
  if [[ -z "$project_selection" ]] && [[ "$action" != "inventory" && "$action" != "i" ]]; then
    read -e -p $'\033[34m- List project(s) of the target devices (comma-separated, or leave blank for all projects):\033[0m ' ${defprojects:+-i "$defprojects"} project_selection
  fi
  
  # Convert project_selection to an array
  IFS=',' read -r -a selected_projects <<< "$project_selection"

  # Prompt to select devices to update (if blank, all will be used)
  if [[ -z "$label_selection" ]] && [[ "$action" != "inventory" && "$action" != "i" ]]; then
    read -e -p $'\033[34m- List labels of the target devices (comma-separated, or leave blank for all devices):\033[0m ' ${deflabels:+-i "$deflabels"} label_selection
  fi

  # Convert label_selection to an array
  IFS=',' read -r -a selected_labels <<< "$label_selection"

  if [[ "$action" != "fetch" && "$action" != "f" ]]; then
    # Get the scope
      if [[ -z "$scope" ]] && [[ "$action" != "inventory" && "$action" != "i" ]]; then
	read -e -p $'\033[34m- Set scope (server/shared; default: shared):\033[0m ' ${defscope:+-i "$defscope"} scope
      fi
      scope=${scope:-SHARED}
      scope=${scope^^}
  fi

  if [[ "$action" == "post" || "$action" == "p" ]]; then
    # Prompt for attribute and value for post action
    read -p $'\033[34m  Attribute name:\033[0m ' attribute
    read -p $'\033[34m  New attribute value:\033[0m ' value
  elif [[ "$action" == "delete" || "$action" == "d" ]]; then
    # Prompt for attribute name for delete action
    read -p $'\033[34m  Attribute name:\033[0m ' attribute
  fi

  # Iterate over each row in the CSV file
  while IFS=',' read -r deviceid name label project
  do
    # Skip the header if it exists
    if [[ "$deviceid" == "deviceid" ]]; then
      continue
    fi

    # Check if the project is in the selection (or process all if no selection is given)
    if [[ ${#selected_projects[@]} -eq 0 || " ${selected_projects[@]} " =~ " $project " ]]; then

	# Check if the device label is in the selection (or process all if no selection is given)
	if [[ ${#selected_labels[@]} -eq 0 || " ${selected_labels[@]} " =~ " $label " ]]; then

	    if [[ "$action" == "post" || "$action" == "p" ]]; then
		# Build the POST URL
		post_url="https://${domain}:443/api/plugins/telemetry/${deviceid}/${scope}_SCOPE"
		
		# Execute the curl command for post
		response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
				"$post_url" \
				-H "accept: application/json" \
				-H "Content-Type: application/json" \
				-H "X-Authorization: Bearer ${AUTH_TOKEN}" \
				-d "{\"${attribute}\": ${value}}")

		# Print results based on HTTP response
		if [[ "$response" == "200" ]]; then
		    echo -e "\033[36m$label ($deviceid)\033[0m \033[35m[${project^^}]\033[0m - \033[32mSuccessfully posted '\033[0m$attribute: $value\033[32m'\033[0m"
		else
		    echo -e "\033[36m$label ($deviceid)\033[0m \033[35m[${project^^}]\033[0m - \033[31mFailed\033[0m to post '\033[32m$attribute: $value\033[31m' (HTTP Code: $response)\033[0m"
		fi

	    elif [[ "$action" == "delete" || "$action" == "d" ]]; then
		# Build the DELETE URL
		delete_url="https://${domain}:443/api/plugins/telemetry/$deviceid/${scope}_SCOPE?keys=$attribute"

		# Make the DELETE request
		response=$(curl -X 'DELETE' \
				"$delete_url" \
				-H "accept: application/json" \
				-H "X-Authorization: Bearer ${AUTH_TOKEN}" \
				--silent --output /dev/null --write-out "%{http_code}")

		# Print results based on HTTP response
		if [[ "$response" == "200" ]]; then
		    echo -e "\033[36m$label ($deviceid)\033[0m \033[35m[${project^^}]\033[0m - \033[32mSuccessfully deleted '\033[0m$attribute\033[31m'\033[0m"
		else
		    echo -e "\033[36m$label ($deviceid)\033[0m \033[35m[${project^^}]\033[0m - \033[31mFailed to delete '\033[0m$attribute\033[31m' (HTTP Code: $response)\033[0m"
		fi

	    elif [[ "$action" == "get" || "$action" == "g" ]]; then
		# Build the GET URL
		get_url="https://${domain}:443/api/plugins/telemetry/DEVICE/$deviceid/values/attributes/${scope}_SCOPE"

		# Execute the curl command for get
		response=$(curl -s -X GET \
				"$get_url" \
				-H "accept: application/json" \
				-H "X-Authorization: Bearer ${AUTH_TOKEN}")

		# Print the retrieved attributes in a formatted way
		if [[ "$response" != "null" && "$response" != "" ]]; then
		    formatted_attributes=$(echo "$response" | jq -r '.[] | "\(.key): \(.value)"' | sed 's/\([^:]*\): \(.*\)/\x1b[33m\1\x1b[0m: \x1b[37m\2\x1b[0m/' | awk '{printf "%s; ", $0} END {printf "\n"}' | sed 's/; $//')
		    echo -e "\033[36m$label ($deviceid)\033[0m \033[35m[${project^^}]\033[0m - \033[32mSuccessfully got current ${scope}_SCOPE attributes:\0033[0m\n      $formatted_attributes"
		else
		    echo -e "\033[36m$label ($deviceid)\033[0m \033[35m[${project^^}]\033[0m - \033[31mFailed to get ${scope}_SCOPE attributes\033[0m"
		fi

 	    elif [[ "$action" == "fetch" || "$action" == "f" ]]; then
	        # Run the fetch.py script with the necessary arguments
	        echo -e "\033[32m  Fetching data for $label ($deviceid)\033[0m…"
		python3 fetch.py "http://${domain}:8080" -u "${login_email}" -p "${password}" -d "${deviceid}" --project "${project^^}" --label "${label}"

	    fi
	fi
    fi
    
  done < "$csv_file"

  # Wait for all background jobs to finish (i.e., fetch.py)
  wait
}

# Main loop for making changes
while true; do
  # Call the interact function
  interact

  # Prompt user to continue or exit
  if [[ -z "$once" ]]; then
    read -p $'\033[34m- Continue with other device(s) and attribute(s)? (Y/n): \033[0m' continue_choice
    if [[ "$continue_choice" = "n" ]]; then
      echo "Exiting…"
      break
    fi
  fi
  unset project_selection
  unset label_selection
  unset action
  unset scope
done

