#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to check if script is run as root
check_root() {
    # Skip root check in Replit environment
    if [[ -n "${REPL_ID}" || -n "${REPL_SLUG}" ]]; then
        return 0
    fi
    
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Ten skrypt wymaga uprawnień roota${NC}"
        exit 1
    fi
}

# Function to check if smartctl is installed
check_smartctl() {
    if ! command -v smartctl &> /dev/null; then
        echo -e "${RED}smartctl nie jest zainstalowany. Zainstaluj pakiet smartmontools${NC}"
        exit 1
    fi
}

# Function to ensure log directory exists
ensure_log_directory() {
    local log_dir="./logs"
    echo "Konfigurowanie logowania w katalogu: $log_dir"
    
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo -e "${RED}Błąd: Brak uprawnień do utworzenia katalogu logów: $log_dir${NC}"
            return 1
        }
    fi
    
    if [ ! -w "$log_dir" ]; then
        echo -e "${RED}Błąd: Brak uprawnień do zapisu w katalogu logów: $log_dir${NC}"
        return 1
    fi
    
    return 0
}

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local log_dir="./logs"
    local log_file="$log_dir/disk_monitor.log"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Check if logging is enabled
    if [ ! -w "$log_dir" ]; then
        return
    fi
    
    echo "$timestamp [$level] $message" >> "$log_file"
}

# Function to get list of disks
get_disks() {
    
    
    local disks=""
    
    # Get SATA/SAS disks
    for disk in $(lsblk -d -o NAME,TYPE | grep 'disk' | awk '{print $1}'); do
        if [[ $disk =~ ^sd|^hd|^vd ]]; then
            disks="$disks $disk"
        fi
    done
    
    # Get NVMe disks
    for disk in $(lsblk -d -o NAME,TYPE | grep 'disk' | awk '{print $1}'); do
        if [[ $disk =~ ^nvme ]]; then
            disks="$disks $disk"
        fi
    done
    
    echo $disks
}

# Function to get disk type (sata/nvme)
get_disk_type() {
    local disk="$1"
    if [[ $disk =~ ^nvme ]]; then
        echo "nvme"
    else
        echo "sata"
    fi
}

# Function to get SMART status
get_smart_status() {
    local disk="$1"
    local type="$2"
    
    
    
    if [ "$type" == "nvme" ]; then
        smartctl -H "/dev/$disk" 2>/dev/null | grep "SMART.*overall-health" | awk '{print $6}'
    else
        smartctl -H "/dev/$disk" 2>/dev/null | grep "SMART overall-health" | awk '{print $6}'
    fi
}

# Function to get disk power-on time in years and days
get_disk_power_on_days() {
    local disk="$1"
    local type="$2"
    
    local power_on_hours
    if [ "$type" == "nvme" ]; then
        power_on_hours=$(smartctl -a "/dev/$disk" 2>/dev/null | grep -i "Power On Hours" | awk '{print $4}')
    else
        power_on_hours=$(smartctl -a "/dev/$disk" 2>/dev/null | grep "Power_On_Hours" | awk '{print $10}')
    fi
    
    if [ -n "$power_on_hours" ]; then
        local total_days=$((power_on_hours / 24))
        local years=$((total_days / 365))
        local remaining_days=$((total_days % 365))
        
        # Handle year format based on the number with proper Polish grammar
        local year_text
        if [ "$years" -eq 0 ]; then
            year_text="lat"
        elif [ "$years" -eq 1 ]; then
            year_text="rok"
        elif [ "$years" -ge 2 ] && [ "$years" -le 4 ]; then
            year_text="lata"
        else
            year_text="lat"
        fi

        # Always show full format with years and days, ensuring both are displayed even if zero
        echo "$years $year_text, $remaining_days dni"
    else
        echo "N/A"
    fi
}

get_disk_health_percentage() {
    local disk="$1"
    local type="$2"
    
    
    
    local health=100
    local info
    
    if [ "$type" == "nvme" ]; then
        info=$(smartctl -a "/dev/$disk" 2>/dev/null)
        local wear_level=$(echo "$info" | grep -i "Percentage Used" | awk '{print $4}')
        if [ ! -z "$wear_level" ]; then
            health=$((100 - wear_level))
        fi
    else
        info=$(smartctl -a "/dev/$disk" 2>/dev/null)
        local reallocated=$(echo "$info" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
        local pending=$(echo "$info" | grep "Current_Pending_Sector" | awk '{print $10}')
        local offline_bad=$(echo "$info" | grep "Offline_Uncorrectable" | awk '{print $10}')
        
        [ ! -z "$reallocated" ] && [ "$reallocated" -gt 0 ] && health=$((health - reallocated * 2))
        [ ! -z "$pending" ] && [ "$pending" -gt 0 ] && health=$((health - pending * 5))
        [ ! -z "$offline_bad" ] && [ "$offline_bad" -gt 0 ] && health=$((health - offline_bad * 10))
    fi
    
    [ "$health" -lt 0 ] && health=0
    [ "$health" -gt 100 ] && health=100
    
    echo "$health"
}

# Function to get mount points for a disk
get_mount_points() {
    local disk="$1"
    
    
    
    local mount_points=$(lsblk -n -o MOUNTPOINT /dev/"$disk"* | grep -v '^$' | sort -u | tr '\n' ', ' | sed 's/,$//')
    if [ -z "$mount_points" ]; then
        echo "Not mounted"
    else
        echo "$mount_points"
    fi
}

# Function to get partition information
# Function to get disk usage information
get_disk_usage() {
    local disk="$1"
    local mount_point
    
    
    
    # Get all mount points for the disk
    mount_point=$(lsblk -n -o MOUNTPOINT /dev/"$disk"* | grep -v '^$' | grep -v '\[SWAP\]' | head -n 1)
    
    if [ -n "$mount_point" ]; then
        local usage=$(df -h "$mount_point" | tail -n 1)
        local used=$(echo "$usage" | awk '{print $3}')
        local percentage=$(echo "$usage" | awk '{print $5}')
        echo "Used: $used ($percentage)"
    else
        echo "Usage information unavailable"
    fi
}

get_partition_info() {
    local disk="$1"
    
    
    
    local partitions
    partitions=$(lsblk -n -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE /dev/"$disk" | grep -v "^$disk " || echo "")
    if [ -n "$partitions" ]; then
        while IFS= read -r line; do
            local name size fstype mountpoint type
            read -r name size fstype mountpoint type <<< "$line"
            local raid_info=""
            if [ "$fstype" == "linux_raid_member" ] || [ "$type" == "raid1" ]; then
                local raid_array=$(lsblk -n -o NAME,TYPE /dev/"$disk"* | grep "raid" | awk '{print $1}' | head -n 1)
                [ -n "$raid_array" ] && raid_info=" [RAID member: /dev/$raid_array]"
            fi
            echo "${name} - ${mountpoint:-Not mounted} (${size}, ${fstype:-unknown})${raid_info}"
        done <<< "$partitions"
    else
        echo "No partitions found"
    fi
}

# Function to get RAID information
get_raid_info() {
    local disk="$1"
    
    
    
    # Check if disk is part of any RAID array
    local raid_part=$(lsblk -n -o NAME,TYPE /dev/"$disk"* | grep "raid" || true)
    if [ -n "$raid_part" ]; then
        # Get the RAID device name (md*)
        local raid_dev=$(echo "$raid_part" | awk '{print $1}' | grep -o 'md[0-9]*')
        if [ -n "$raid_dev" ]; then
            local raid_detail=$(mdadm --detail /dev/"$raid_dev" 2>/dev/null)
            if [ -n "$raid_detail" ]; then
                local status="Active"
                local level=$(echo "$raid_detail" | grep "Raid Level" | sed 's/.*: //')
                local devices=$(echo "$raid_detail" | grep "Raid Devices" | awk '{print $4}')
                local size=$(echo "$raid_detail" | grep "Array Size" | sed 's/.*: //' | cut -d' ' -f1-2)
                local state=$(echo "$raid_detail" | grep "State :" | sed 's/.*: //')
                local health=$(echo "$raid_detail" | grep -i "Failed Devices" | awk '{print $4}')
                [ "$health" == "0" ] && health="Optimal" || health="Degraded"
                
                echo -e "Status: $status\nType: $level\nArray: /dev/$raid_dev\nRaid devices: $devices\nState: $state\nTotal Size: $size\nRAID Health: $health"
            else
                echo "RAID configuration detected but details unavailable"
            fi
        else
            echo "RAID configuration detected but array information unavailable"
        fi
    else
        echo "No RAID configuration"
    fi
}

# Function to get disk information
get_disk_info() {
    local disk="$1"
    local type="$2"
    
    
    
    local info
    if [ "$type" == "nvme" ]; then
        info=$(smartctl -a "/dev/$disk" 2>/dev/null)
        local model=$(echo "$info" | grep -i "Model Number" | awk -F': ' '{print $2}')
        local size=$(echo "$info" | grep -i "Total NVM Capacity" | awk -F': ' '{print $2}')
        local temp=$(echo "$info" | grep -i "Temperature:" | awk '{print $2}')
    else
        info=$(smartctl -a "/dev/$disk" 2>/dev/null)
        local vendor=$(echo "$info" | grep "Vendor:" | awk -F': ' '{print $2}')
        [ -z "$vendor" ] && vendor=$(echo "$info" | grep -i "Model Family" | awk -F': ' '{print $2}')
        local model=$(echo "$info" | grep "Device Model" | awk -F': ' '{$1=$1;print $0}')
        [ -z "$model" ] && model=$(echo "$info" | grep "Product:" | awk -F': ' '{$1=$1;print $0}')
        local size=$(echo "$info" | grep "User Capacity" | awk -F'[' '{print $2}' | awk -F']' '{print $1}')
        local temp=$(echo "$info" | grep "Temperature_Celsius" | awk '{print $10}')
    fi

    local serial
    if [ "$type" == "nvme" ]; then
        serial=$(echo "$info" | grep -i "Serial Number" | awk -F': ' '{print $2}')
    else
        serial=$(echo "$info" | grep "Serial Number" | awk -F': ' '{print $2}')
    fi
    
    echo -e "Producent/Model: ${vendor:-Unknown} / ${model:-Unknown}"
    echo -e "Serial Number: $serial"
    echo -e "Size: $size"
    echo -e "Temperature: ${temp}°C"
    local power_on_days=$(get_disk_power_on_days "$disk" "$type")
    echo -e "Czas pracy: ${power_on_days}"
    local health_percentage=$(get_disk_health_percentage "$disk" "$type")
    if [ "$health_percentage" == "100" ]; then
        echo -e "Health: ${GREEN}${health_percentage}%${NC}"
        log_message "INFO" "Dysk /dev/$disk - stan zdrowia: $health_percentage%"
    else
        echo -e "Health: ${RED}${health_percentage}%${NC}"
        if [ "$health_percentage" -lt 50 ]; then
            log_message "WARNING" "Dysk /dev/$disk - krytycznie niski stan zdrowia: $health_percentage%"
        else
            log_message "INFO" "Dysk /dev/$disk - stan zdrowia: $health_percentage%"
        fi
    fi
    echo -e "Mount points: $(get_mount_points "$disk")"
    echo -e "$(get_disk_usage "$disk")"
    echo -e "\nPartycje:"
    echo -e "$(get_partition_info "$disk")"
}

# Function to display disk details
display_disk_info() {
    local disk="$1"
    local type=$(get_disk_type "$disk")
    local status=$(get_smart_status "$disk" "$type")
    
    echo -e "\n${YELLOW}=== Disk /dev/$disk - ${type^^} ===${NC}"
    
    if [ "$status" == "PASSED" ] || [ "$status" == "OK" ]; then
        echo -e "SMART Status: ${GREEN}$status${NC}"
    else
        echo -e "SMART Status: ${RED}$status${NC}"
        log_message "WARNING" "Dysk /dev/$disk - wykryto problem SMART. Status: $status"
    fi
    
    get_disk_info "$disk" "$type"
}

# Function to display RAID information
display_raid_info() {
    local raid_arrays=($(ls /dev/md* 2>/dev/null | grep -o 'md[0-9]*' || true))
    
    if [ ${#raid_arrays[@]} -eq 0 ]; then
        echo -e "\n${YELLOW}=== RAID Arrays ===${NC}"
        echo "No RAID arrays detected"
        return
    fi
    
    # Use associative array to prevent duplicates
    declare -A seen_arrays
    
    echo -e "\n${YELLOW}=== RAID Arrays ===${NC}"
    for array in "${raid_arrays[@]}"; do
        # Skip if we've already seen this array
        [ "${seen_arrays[$array]}" == "1" ] && continue
        seen_arrays[$array]="1"
        
        local raid_detail=$(mdadm --detail /dev/"$array" 2>/dev/null)
        if [ -n "$raid_detail" ]; then
            echo -e "\nArray: /dev/$array"
            
            # Get raid level (type)
            local raid_level=$(echo "$raid_detail" | grep "Raid Level" | sed 's/.*: //')
            echo "Type: $raid_level"
            
            # Pobranie stanu i konwersja na wielkie litery
            local state=$(echo "$raid_detail" | grep "State :" | sed 's/.*: //' | tr '[:lower:]' '[:upper:]')
            
            # System kolorowania statusów RAID Array
            # Stany i ich kolory:
            # Zielony (${GREEN}): CLEAN, ACTIVE - stany optymalne
            # Czerwony (${RED}): DEGRADED, FAULTY, INACTIVE, REMOVED - stany problematyczne
            # Pomarańczowy (${YELLOW}): RESYNCING, RECOVERING, SPARE, REBUILDING - stany przejściowe
            local state_color="${RED}"  # domyślnie czerwony dla nieznanych stanów
            local message
            
            case "$state" in
                # Stany optymalne - kolor zielony
                "CLEAN"|"ACTIVE")
                    state_color="${GREEN}"
                    message="stan optymalny"
                    log_message "INFO" "RAID /dev/$array - stan optymalny: $state"
                    ;;
                # Stany przejściowe - kolor pomarańczowy
                "RESYNCING"|"RECOVERING"|"SPARE"|"REBUILDING")
                    state_color="${YELLOW}"
                    message="stan przejściowy"
                    log_message "INFO" "RAID /dev/$array - stan przejściowy: $state"
                    ;;
                # Stany problematyczne - kolor czerwony
                "DEGRADED"|"FAULTY"|"INACTIVE"|"REMOVED")
                    state_color="${RED}"
                    message="stan problematyczny"
                    log_message "WARNING" "RAID /dev/$array - stan problematyczny: $state"
                    ;;
                *)
                    state_color="${RED}"
                    message="nieznany stan"
                    log_message "WARNING" "RAID /dev/$array - wykryto nieznany stan: $state"
                    ;;
            esac
            
            # Wyświetlenie stanu macierzy z pogrubieniem
            echo -e "RAID state: \033[1m${state}\033[0m"
            
            # Get and format size properly
            local size=$(echo "$raid_detail" | grep "Array Size" | sed 's/.*: //')
            size=$(echo "$size" | awk '{printf "%.2f %s", $1/1024/1024, "GB"}')
            echo -e "Size: $size"
            
            # Get device counts
            local total_devs=$(echo "$raid_detail" | grep "Raid Devices" | awk '{print $4}')
            local active_devs=$(echo "$raid_detail" | grep "Active Devices" | awk '{print $4}')
            local failed_devs=$(echo "$raid_detail" | grep "Failed Devices" | awk '{print $4}')
            
            # Calculate health status and color
            local health_status="OPTIMAL"
            local health_color="${GREEN}"
            if [ "$failed_devs" -gt 0 ]; then
                health_status="DEGRADED"
                health_color="${RED}"
            fi
            

            # Logowanie informacji o uszkodzonych urządzeniach
            if [ "$failed_devs" -gt 0 ]; then
                log_message "WARNING" "RAID /dev/$array - liczba uszkodzonych urządzeń: $failed_devs"
            fi
            
            # Logowanie stanu zdrowia macierzy
            if [ "$health_status" != "OPTIMAL" ]; then
                log_message "WARNING" "RAID /dev/$array - stan zdrowia: $health_status (Aktywne: $active_devs/$total_devs)"
            else
                log_message "INFO" "RAID /dev/$array - stan zdrowia: $health_status (Aktywne: $active_devs/$total_devs)"
            fi

            # Display health status
            echo -e "Health: \033[1m${health_status}\033[0m (Active: $active_devs/$total_devs, Failed: $failed_devs)"
            
            # List member disks
            echo "Member Disks:"
            echo "$raid_detail" | grep "/dev/sd" | sort | uniq | awk '{print "  - "$7}'
        fi
    done
}

main() {
    check_root
    check_smartctl
    
    # Ensure log directory exists and is writable
    ensure_log_directory || echo -e "${YELLOW}Uwaga: Logowanie zostało wyłączone z powodu problemów z dostępem${NC}"
    
    echo -e "${YELLOW}=== Disk Health Monitor ===${NC}"
    echo -e "Starting disk health check at $(date)"
    log_message "INFO" "Rozpoczęto sprawdzanie stanu dysków"
    
    local disks=($(get_disks))
    
    if [ ${#disks[@]} -eq 0 ]; then
        echo -e "${RED}No supported disks found${NC}"
        log_message "ERROR" "Nie znaleziono obsługiwanych dysków"
        exit 1
    fi
    
    for disk in "${disks[@]}"; do
        display_disk_info "$disk"
    done
    
    display_raid_info
    
    echo -e "\n${YELLOW}=== Check completed ===${NC}"
    log_message "INFO" "Zakończono sprawdzanie stanu dysków"
}

# Run main function
main
