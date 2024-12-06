#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define log directory and file
LOG_DIR="/"
LOG_FILE="disk_monitor.log"

# Function to ensure log directory exists and is writable
ensure_log_directory() {
    echo "Konfigurowanie logowania w katalogu: $LOG_DIR"
    
    # Create log directory if it doesn't exist
    if [ ! -d "$LOG_DIR" ]; then
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            echo -e "${RED}Błąd: Nie można utworzyć katalogu logów: $LOG_DIR${NC}"
            return 1
        fi
    fi
    
    # Verify write permissions to directory
    if [ ! -w "$LOG_DIR" ]; then
        echo -e "${RED}Błąd: Brak uprawnień do zapisu w katalogu logów: $LOG_DIR${NC}"
        return 1
    fi
    
    # Create or verify log file
    if [ ! -f "$LOG_FILE" ]; then
        if ! touch "$LOG_FILE" 2>/dev/null; then
            echo -e "${RED}Błąd: Nie można utworzyć pliku logów: $LOG_FILE${NC}"
            return 1
        fi
    elif [ ! -w "$LOG_FILE" ]; then
        echo -e "${RED}Błąd: Brak uprawnień do zapisu w pliku logów: $LOG_FILE${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Pomyślnie skonfigurowano logowanie w: $LOG_FILE${NC}"
    return 0
}


# Disk Monitor - Script for monitoring disk health using SMART data
# Requires: smartmontools package

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file location
if [ "$REPLIT_DEV_MODE" == "true" ]; then
    LOG_FILE="./disk_monitor.log"
else
    LOG_FILE="/var/log/disk_monitor.log"
fi



# Function to log messages with severity levels
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Skip logging if directory check failed
    [ -f "$LOG_FILE" ] || return 1
    
    local log_entry
    case "$level" in
        "INFO")
            log_entry="$timestamp [INFO] $message"
            ;;
        "WARNING")
            log_entry="$timestamp [WARNING] $message"
            ;;
        "ERROR")
            log_entry="$timestamp [ERROR] $message"
            ;;
        *)
            log_entry="$timestamp [INFO] $message"
            ;;
    esac
    
    if ! echo "$log_entry" >> "$LOG_FILE" 2>/dev/null; then
        echo -e "${RED}Błąd: Nie można zapisać do pliku logów: $LOG_FILE${NC}" >&2
        return 1
    fi
}

# Function to check if running as root
check_root() {
    if [ "$REPLIT_DEV_MODE" != "true" ] && [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Uwaga: Skrypt uruchomiony bez uprawnień roota - niektóre funkcje mogą być ograniczone${NC}"
        # Nie przerywamy działania skryptu, ale informujemy użytkownika
        return 1
    fi
    return 0
}

# Function to check if smartctl is installed
check_smartctl() {
    if ! command -v smartctl &> /dev/null; then
        echo -e "${RED}Error: smartctl is not installed. Please install smartmontools package${NC}"
        log_message "ERROR" "smartctl not found - nie można kontynuować monitorowania"
        exit 1
    fi
}

# Function to get all disk devices
get_disks() {
    local disks=($(lsblk -d -n -o NAME | grep -E '^(sd[a-z]+|nvme[0-9]+n[0-9]+)$'))
    echo "${disks[@]}"
}

# Function to determine disk type (SATA/NVMe)
get_disk_type() {
    local disk="$1"
    if [[ $disk == nvme* ]]; then
        echo "nvme"
    else
        echo "sata"
    fi
}

# Function to get SMART status for a disk
get_smart_status() {
    local disk="$1"
    local type="$2"
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        # Symulowane dane w trybie developerskim
        if [ "$disk" == "sda" ]; then
            echo "PASSED"
        elif [ "$disk" == "sdb" ]; then
            echo "FAILED"
        else
            echo "PASSED"
    # Log SMART status changes
    if [ -n "$status" ]; then
        if [ "$status" != "PASSED" ] && [ "$status" != "OK" ]; then
            log_message "WARNING" "Dysk /dev/$disk - nieprawidłowy status SMART: $status"
        else
            log_message "INFO" "Dysk /dev/$disk - status SMART: $status"
        fi
    fi
        fi
        return
    fi

    local status
    if [ "$type" == "nvme" ]; then
        status=$(smartctl -H "/dev/$disk" 2>/dev/null | grep -i "smart overall-health" | awk '{print $NF}')
    else
        status=$(smartctl -H "/dev/$disk" 2>/dev/null | grep -i "smart overall-health" | awk '{print $NF}')
    fi
    
    # Log SMART status changes
    if [ -n "$status" ]; then
        if [ "$status" != "PASSED" ] && [ "$status" != "OK" ]; then
            log_message "WARNING" "Dysk /dev/$disk - nieprawidłowy status SMART: $status"
        else
            log_message "INFO" "Dysk /dev/$disk - status SMART: $status"
        fi
    fi

    if [ -z "$status" ]; then
        echo "UNKNOWN"
    else
        echo "$status"
    fi
}

# Function to get disk health percentage
get_disk_health_percentage() {
    local disk="$1"
    local type="$2"
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        case "$disk" in
            "sda")
                echo "95"
                ;;
            "sdb")
                echo "45"
                ;;
            *)
                echo "85"
                ;;
        esac
        return
    fi
    
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
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        case "$disk" in
            "sda")
                echo "/"
                ;;
            "sdb")
                echo "/home"
                ;;
            "sdc")
                echo "/mnt/data"
                ;;
            *)
                echo "Not mounted"
                ;;
        esac
        return
    fi
    
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
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        case "$disk" in
            "sda")
                echo "Used: 234GB (47%)"
                ;;
            "sdb")
                echo "Used: 2.1TB (60%)"
                ;;
            "sdc")
                echo "Used: 756GB (75%)"
                ;;
            *)
                echo "Usage information unavailable"
                ;;
        esac
        return
    fi
    
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
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        case "$disk" in
            "sda")
                echo -e "sda1 - / (50GB, ext4)\nsda2 - swap (8GB)"
                ;;
            "sdb")
                echo -e "sdb1 - /home (3.5TB, ext4)\nsdb2 - swap (8GB)"
                ;;
            "sdc")
                echo -e "sdc1 - /mnt/data (1TB, ext4)"
                ;;
            *)
                echo "No partitions found"
                ;;
        esac
        return
    fi
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        case "$disk" in
            "sda")
                echo "sda1 - / (50GB, ext4)"
                echo "sda2 - swap (8GB)"
                ;;
            "sdb")
                echo "sdb1 - /home (3.5TB, ext4)"
                echo "sdb2 - swap (8GB)"
                ;;
            "sdc")
                echo "sdc1 - /mnt/data (1TB, ext4)"
                ;;
            *)
                echo "No partitions found"
                ;;
        esac
        return
    fi
    
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
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        case "$disk" in
            "sda")
                echo -e "Status: Active\nType: RAID 1 (Mirror)\nArray: /dev/md0\nMount: /\nRaid devices: 2\nState: clean\nTotal Size: 2TB\nRAID Health: Optimal"
                ;;
            "sdb")
                echo -e "Status: Active\nType: RAID 1 (Mirror)\nArray: /dev/md0\nMount: /\nRaid devices: 2\nState: clean\nTotal Size: 2TB\nRAID Health: Optimal"
                ;;
            "sdc")
                echo "No RAID configuration"
                ;;
            *)
                echo "No RAID configuration"
                ;;
        esac
        return
    fi
    
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
    
    if [ "$REPLIT_DEV_MODE" == "true" ]; then
        if [ "$type" == "nvme" ]; then
            echo -e "Producent/Model: Samsung / 970 EVO Plus NVMe SSD"
            echo -e "Serial Number: S4EDNX0M614821K"
            echo -e "Size: 1TB"
            echo -e "Temperature: 45°C"
            echo -e "Health: $(get_disk_health_percentage "$disk" "$type")%"
            echo -e "Mount points: $(get_mount_points "$disk")"
            echo -e "\nPartycje:"
            echo -e "$(get_partition_info "$disk")"
            echo -e "\nInformacje o RAID:"
            echo -e "$(get_raid_info "$disk")"
        else
            case "$disk" in
                "sda")
                    echo -e "Producent/Model: Western Digital / Blue HDD"
                    echo -e "Serial Number: WD-WXC1A75LC4K1"
                    echo -e "Size: 2TB"
                    echo -e "Temperature: 35°C"
                    echo -e "Health: $(get_disk_health_percentage "$disk" "$type")%"
                    echo -e "Mount points: $(get_mount_points "$disk")"
                    echo -e "\nPartycje:"
                    echo -e "$(get_partition_info "$disk")"
                    echo -e "\nInformacje o RAID:"
                    echo -e "$(get_raid_info "$disk")"
                    ;;
                "sdb")
                    echo -e "Producent/Model: Seagate / Barracuda HDD"
                    echo -e "Serial Number: ZCH0KL4M"
                    echo -e "Size: 4TB"
                    echo -e "Temperature: 52°C"
                    echo -e "Health: $(get_disk_health_percentage "$disk" "$type")%"
                    echo -e "Mount points: $(get_mount_points "$disk")"
                    echo -e "\nPartycje:"
                    echo -e "$(get_partition_info "$disk")"
                    echo -e "\nInformacje o RAID:"
                    echo -e "$(get_raid_info "$disk")"
                    ;;
                *)
                    echo -e "Model: Generic HDD"
                    echo -e "Serial Number: UNKNOWN"
                    echo -e "Size: 1TB"
                    echo -e "Temperature: 40°C"
                    echo -e "Health: $(get_disk_health_percentage "$disk" "$type")%"
                    echo -e "Mount points: $(get_mount_points "$disk")"
                    echo -e "\nPartycje:"
                    echo -e "$(get_partition_info "$disk")"
                    echo -e "\nInformacje o RAID:"
                    echo -e "$(get_raid_info "$disk")"
                    ;;
            esac
        fi
        return
    fi
    
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

# Main function
# Function to display RAID information
display_raid_info() {
    local raid_arrays=($(ls /dev/md* 2>/dev/null | grep -o 'md[0-9]*' || true))
    
    if [ ${#raid_arrays[@]} -eq 0 ]; then
        if [ "$REPLIT_DEV_MODE" == "true" ]; then
            # Symulowane dane w trybie developerskim
            echo -e "\n${YELLOW}=== RAID Arrays ===${NC}"
            echo -e "\nArray: /dev/md0"
            echo "Type: RAID 1 (Mirror)"
            echo -e "State: ${GREEN}active${NC}"
            echo "Size: 1862.89 GB"
            echo "Health: Optimal (Active: 2/2, Failed: 0)"
            echo "Member Disks:"
            echo "  - /dev/sdc1"
            echo "  - /dev/sdb1"
            return
        else
            echo -e "\n${YELLOW}=== RAID Arrays ===${NC}"
            echo "No RAID arrays detected"
            return
        fi
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
            
# Get state and color it appropriately
            local state=$(echo "$raid_detail" | grep "State :" | sed 's/.*: //')
            case "${state,,}" in
                "active"|"clean")
                    echo -e "State: ${RED}${state}${NC}"
                    ;;
                *)
                    echo -e "State: ${GREEN}${state}${NC}"
                    ;;
            esac
            
            # Get and format size properly
            local size=$(echo "$raid_detail" | grep "Array Size" | sed 's/.*: //')
            size=$(echo "$size" | awk '{printf "%.2f %s", $1/1024/1024, "GB"}')
            echo "Size: $size"
            
            # Get device counts
            local total_devs=$(echo "$raid_detail" | grep "Raid Devices" | awk '{print $4}')
            local active_devs=$(echo "$raid_detail" | grep "Active Devices" | awk '{print $4}')
            local failed_devs=$(echo "$raid_detail" | grep "Failed Devices" | awk '{print $4}')
            
            # Calculate health status
            [ "$failed_devs" == "0" ] && local health="Optimal" || local health="Degraded"
            
            # Log RAID state and health information
            if [ -n "$state" ]; then
                if [[ "${state,,}" =~ ^(active|clean)$ ]]; then
                    log_message "INFO" "RAID /dev/$array - stan: $state"
                else
                    log_message "WARNING" "RAID /dev/$array - wykryto nieprawidłowy stan: $state"
                fi
            fi

            if [ "$failed_devs" -gt 0 ]; then
                log_message "WARNING" "RAID /dev/$array - liczba uszkodzonych urządzeń: $failed_devs"
            fi
            
            if [ "$health" != "Optimal" ]; then
                log_message "WARNING" "RAID /dev/$array - stan zdrowia: $health (Aktywne: $active_devs/$total_devs)"
            else
                log_message "INFO" "RAID /dev/$array - stan zdrowia: $health (Aktywne: $active_devs/$total_devs)"
            fi

            echo "Health: $health (Active: $active_devs/$total_devs, Failed: $failed_devs)"
            
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
