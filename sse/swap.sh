#!/usr/bin/env bash
#
# swap.sh - Swap management and configuration

swap_management_menu() {
    while true; do
        section_title "Swap Management"
        echo
        echo "   1) Auto-configure swap (intelligent detection)"
        echo "   2) Set custom swap size"
        echo "   3) Clean up all swap files and start fresh"
        echo "   4) Show Current Swap Details"
        echo "   0) Back to Main Menu"
        echo
        
        read -rp "   Choose option [0-4]: " choice
        case $choice in
            1)
                local recommended=$(recommended_swap_mb)
                [[ $recommended -gt 0 ]] && setup_swap $recommended || log_ok "System has sufficient RAM - no swap recommended"
                pause
                ;;
            2)
                read -rp "Enter swap size in MB: " custom_size
                [[ $custom_size =~ ^[0-9]+$ ]] && [[ $custom_size -gt 0 ]] && setup_swap $custom_size || log_error "Invalid size entered"
                pause
                ;;
            3)
                log_info "Starting fresh swap configuration..."
                cleanup_existing_swap
                log_ok "System is now clean. Use option 1 or 2 to configure new swap."
                pause
                ;;
            4)
                echo -e "${BOLD}Swap Details:${RESET}"
                free -h; echo; cat /proc/swaps 2>/dev/null || log_info "No swap files active"; echo
                pause
                ;;
            0) return ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

cleanup_existing_swap() {
    log_info "Cleaning up existing swap configuration..."
    
    local active_swaps=$(awk 'NR>1 {print $1}' /proc/swaps 2>/dev/null || true)
    if [[ -n "$active_swaps" ]]; then
        log_info "Disabling active swap files..."
        swapoff -a 2>/dev/null || log_warn "Some swap files could not be disabled (may be in use)"
    fi
    
    local swap_files=("${SSE_SWAPFILE}" "/swapfile.new" "/swapfile2" "/tmp/temp_swap_"*)
    for file in "${swap_files[@]}"; do
        [[ -f "$file" ]] && { log_info "Removing: $file"; rm -f "$file" 2>/dev/null || log_warn "Could not remove: $file"; }
    done
    
    grep -q "${SSE_SWAPFILE}" /etc/fstab 2>/dev/null && {
        log_info "Cleaning /etc/fstab..."
        sed -i "\#${SSE_SWAPFILE}#d" /etc/fstab 2>/dev/null || true
    }
    
    log_ok "Cleanup completed"
}

create_swap_file() {
    local file_path="$1" size_mb="$2"
    local available_mb=$(get_disk_available_mb)
    
    [[ $available_mb -lt $size_mb ]] && {
        log_error "Insufficient disk space. Available: ${available_mb}MB, Required: ${size_mb}MB"
        return 1
    }
    
    log_info "Creating swap file: ${file_path} (${size_mb}MB)"
    
    # Touch the file first to check filesystem
    touch "$file_path"
    
    # Detect Btrfs and disable Copy-on-Write
    local fs_type=$(df -T "$(dirname "$file_path")" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ "$fs_type" == "btrfs" ]]; then
        log_info "Btrfs filesystem detected. Disabling Copy-on-Write for swap file..."
        chattr +C "$file_path" 2>/dev/null || log_warn "Failed to disable CoW on Btrfs. Kernel panic may occur!"
    fi
    
    if command -v fallocate >/dev/null 2>&1 && [[ "$fs_type" != "btrfs" ]]; then
        # fallocate may fail on some filesystems like ZFS or older ext3
        fallocate -l "${size_mb}M" "$file_path" || {
            log_warn "fallocate failed, using dd..."
            dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none || {
                log_error "Failed to create swap file"; return 1; }
        }
    else
        # Btrfs requires using dd and avoiding fallocate
        dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none || {
            log_error "Failed to create swap file"; return 1; }
    fi
    
    chmod 600 "$file_path" || { log_error "Failed to set permissions"; return 1; }
    mkswap "$file_path" >/dev/null 2>&1 || { log_error "Failed to format swap file"; rm -f "$file_path"; return 1; }
    swapon "$file_path" || { log_error "Failed to enable swap file"; rm -f "$file_path"; return 1; }
    
    log_ok "Swap file created and enabled successfully"
    return 0
}

setup_swap() {
    local target_mb="$1"
    local current_swap=$(get_swap_total_mb)
    local current_swap_file_size=$(get_swap_file_size_mb "$SSE_SWAPFILE")
    
    if [[ -f "$SSE_SWAPFILE" ]] && [[ $current_swap_file_size -eq $target_mb ]] && [[ $current_swap -eq $target_mb ]]; then
        log_ok "Swap already configured with recommended size: ${target_mb}MB - no changes needed"
        return 0
    fi
    
    section_title "Configuring Swap: ${current_swap}MB → ${target_mb}MB"
    cleanup_existing_swap
    
    if create_swap_file "$SSE_SWAPFILE" "$target_mb"; then
        echo "$SSE_SWAPFILE none swap sw 0 0" >> /etc/fstab
        log_ok "Swap configuration completed successfully"
        echo; free -h; echo; cat /proc/swaps
    else
        log_error "Failed to configure swap"
        return 1
    fi
}
