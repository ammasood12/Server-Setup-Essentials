#!/usr/bin/env bash
#
# benchmark.sh - Benchmarks and media checking tools

benchmark_menu() {
    while true; do
        section_title "Benchmark & Media Checking Tools"
        echo -e "${CYAN}Collection of useful online benchmarking and testing tools:${RESET}"
        echo
        echo -e "   ── ${YELLOW}Full Benchmark Tools${RESET} ──────────────────────────────"        
        
        echo "   1) YABS (Yet Another Benchmark Script)"
        echo "   2) Bench.sh (Full System Benchmark)"
        echo "   3) spiritLHLS/ecs Full Check (bash.spiritlhl.net/ecs)"
        
        echo -e "   ── ${YELLOW}Media Checking Tools${RESET} ─────────────────────────"
        
        echo "   5) BackBone Check 1 (ludashi2020/backtrace)"
        echo "   6) BackBone Check 2 (route.f2k.pub)"
        
        echo "   7) Check Media 1 (Check.Unlock.Media)"
        echo "   8) Check Media 2 (Media.Check.Place)"
        echo "   9) Check Media Quality (Check.Place)"
        
        echo -e "   ─────────────────────────────────────────────────"		
        echo "   10) Check System Detailed Information"
        
        echo -e "   ── ${YELLOW}SpeedTest Tools${RESET} ─────────────────────────"
        
        echo "   11) Speedtest - Ookla Speedtest CLI"
        echo "   12) Speedtest - Libre (Multi Country)"
        
        echo
        echo "   0) Back to Main Menu"
        echo
        
        read -rp "   Choose option [0-12]: " choice
        case $choice in		
            1) run_yabs; pause ;;
            2) run_generic_command \
                "Bench.sh" \
                "interactive" \
                "wget -qO- bench.sh | bash" \
                "Classic interactive system benchmark" \
                "bench.sh";
                pause ;;
            3)  run_generic_command \
                "spiritLHLS/ecs Check" \
                "exec" \
                "bash <(wget -qO- bash.spiritlhl.net/ecs) -en" \
                "VPS Fusion Monster Server Test Script" \
                "bash.spiritlhl.net/ecs"; pause ;;
            5) run_generic_command \
                "BackBone Check 1" \
                "interactive" \
                "curl -sSf https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh | bash" \
                "Interactive backbone connectivity check script" \
                "https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh";
                pause ;;
            6) run_generic_command \
                "BackBone Check 2" \
                "interactive" \
                "wget -q route.f2k.pub -O route && bash route && rm -f route" \
                "Interactive backbone connectivity check script" \
                "route.f2k.pub";
                pause ;;
            7) run_generic_command \
                "Media Check 1 (unlock.media)" \
                "interactive" \
                "bash <(curl -L -s check.unlock.media) -E en" \
                "Interactive media unlock status check" \
                "check.unlock.media";
                pause ;;			
            8) run_generic_command \
                "Media Check 2 (Media.Check.Place)" \
                "interactive" \
                "bash <(curl -sL Media.Check.Place) -E en" \
                "Interactive media unlock status check" \
                "Media.Check.Place";
                pause ;;		
            9) run_generic_command \
                "Media Quality Check" \
                "interactive" \
                "bash <(curl -Ls Check.Place) -E" \
                "Interactive media streaming quality check" \
                "Check.Place";
                pause ;;			
            10) run_generic_command \
                "Check System Detailed Information" \
                "direct" \
                "wget -qO - https://raw.github.com/tdulcet/Linux-System-Information/master/info.sh | bash -s" \
                "Non-interactive system information check script" \
                "https://raw.github.com/tdulcet/Linux-System-Information/master/info.sh";
                pause ;;
            11) run_speedtest; pause ;;
            12)  run_generic_command \
                "Run Libre SpeedTest" \
                "exec" \
                "curl -sSL bench.sh | bash" \
                "Libre SpeedTest script" \
                "N/A"; pause ;;
            0) return ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

run_generic_command() {
    local command_name="$1"
    local command_type="$2"
    local command="$3"
    local description="$4"
    local source_info="$5"
    
    section_title "$command_name"
    
    if [[ -n "$description" ]]; then
        echo -e "${YELLOW}Note: $description${RESET}"
    fi
    
    if [[ -n "$source_info" ]]; then
        echo -e "${YELLOW}Source: $source_info${RESET}"
    fi
    
    echo -e "${YELLOW}Command: $command${RESET}"
    echo
    
    if [[ "$command_type" == "exec" ]]; then
        echo -e "${RED}Note: This will exit this menu and run the external script directly.${RESET}"		
    fi
    
    read -rp "   Are you sure you want to continue? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Cancelled"; return 1; }
    
    log_info "Running $command_name..."
    echo -e "${CYAN}Executing: $command${RESET}"
    echo
    
    local exit_code=0
    
    case "$command_type" in
        "direct")
            eval "$command"
            exit_code=$?
            ;;
        "pipe")
            bash -c "$command"
            exit_code=$?
            ;;
        "eval")
            eval "$command"
            exit_code=$?
            ;;
        "interactive")
            log_info "Running interactive command. Use Ctrl+C to exit."
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
            eval "$command"
            exit_code=$?
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
            ;;
        "exec")
            log_info "Exiting menu and executing: $command"
            exec bash -c "$command"
            ;;
        *)
            log_error "Unknown command type: $command_type"
            return 1
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 130 ]] || [[ $exit_code -eq 143 ]]; then
        log_ok "$command_name completed"
        return 0
    else
        log_error "$command_name failed (exit code: $exit_code)"
        return $exit_code
    fi
}

run_yabs() {
    section_title "Running YABS (Yet Another Benchmark Script)"
    
    echo "   Select benchmark options:"
    echo "   1) Full YABS (default)"
    echo "   2) YABS without Geekbench"
    echo "   3) YABS without disk test"
    echo "   4) Custom flags"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-4]: " yabs_choice
    
    [[ "$yabs_choice" == "0" ]] && { log_warn "Cancelled"; return 1; }
    
    local yabs_flags=""
    case $yabs_choice in
        1) yabs_flags="" ;;
        2) yabs_flags="-i" ;;
        3) yabs_flags="-d" ;;
        4)
            echo "   Available flags:"
            echo "   -i : skip Geekbench system performance test"
            echo "   -d : skip fio disk performance test"
            echo "   -r : skip speedtest network performance test"
            echo "   -w : skip WireGuard network stack test"
            echo "   Example: -id (skip both Geekbench and disk test)"
            read -rp "   Enter flags (without dash): " custom_flags
            [[ -n "$custom_flags" ]] && yabs_flags="-$custom_flags"
            ;;
        *) log_warn "Invalid choice"; return 1 ;;
    esac
    
    run_generic_command \
        "YABS Benchmark" \
        "interactive" \
        "curl -sL yabs.sh | bash $yabs_flags" \
        "Interactive comprehensive system testing" \
        "yabs.sh"
}

execute_speedtest() {
    local test_name="$1"
    local speedtest_cmd="$2"
    local target_info="${3:-Automatic Optimal}"
    local log_file="${SSE_SPEEDTEST_LOG_FILE:-/root/speedtest.log}"
    
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    
    section_title "$test_name"
    echo -e "${YELLOW}Target:   $target_info${RESET}"
    echo -e "${YELLOW}Command:  $speedtest_cmd${RESET}"
    echo -e "${YELLOW}Log File: $log_file${RESET}"
    echo
    
    read -rp "   Proceed with this speedtest? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Speedtest cancelled"; return 1; }
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    
    log_info "Running $test_name..."
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
    
    local temp_output
    temp_output=$(mktemp)
    
    # Run speedtest interactively, live-stream to terminal, and capture to temp file
    eval "$speedtest_cmd 2>&1" | tee "$temp_output"
    local exit_code=${PIPESTATUS[0]}
    
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
    
    # Save cleanly formatted history entry to log file
    {
        echo "════════════════════════════════════════════════════════════════════"
        echo "📌 Speedtest:   $test_name"
        echo "📅 Date & Time: $timestamp"
        echo "🎯 Target:      $target_info"
        echo "⚙️  Command:     $speedtest_cmd"
        echo "────────────────────────────────────────────────────────────────────"
        if [[ -f "$temp_output" ]]; then
            sed -E "s/\x1B\[[0-9;]*[a-zA-Z]//g" "$temp_output" | tr -d '\r'
            rm -f "$temp_output"
        fi
        echo "════════════════════════════════════════════════════════════════════"
        echo
    } >> "$log_file"
    
    if [[ $exit_code -eq 0 ]]; then
        log_ok "Speedtest completed successfully!"
        log_ok "Results saved to: $log_file"
    else
        log_warn "Speedtest finished with exit code $exit_code"
        log_info "Check log file for details: $log_file"
    fi
    
    return $exit_code
}

view_speedtest_history() {
    local log_file="${SSE_SPEEDTEST_LOG_FILE:-/root/speedtest.log}"
    section_title "Speedtest History"
    
    if [[ -f "$log_file" && -s "$log_file" ]]; then
        echo -e "${CYAN}Log file: ${log_file}${RESET}"
        echo
        cat "$log_file"
        echo
        read -rp "   Do you want to clear this speedtest history? (y/N): " clear_confirm
        if [[ $clear_confirm =~ ^[Yy]$ ]]; then
            > "$log_file"
            log_ok "Speedtest history cleared"
        fi
    else
        log_warn "No speedtest history found at $log_file"
    fi
}

run_speedtest() {
    section_title "Running Speedtest (Official Ookla CLI)"
    
    if ! is_ookla_speedtest; then
        log_info "Official Ookla Speedtest CLI not detected. Installing..."
        install_ookla_speedtest || {
            log_error "Could not install official Ookla Speedtest CLI"
            return 1
        }
    fi
    
    echo "   Speedtest options:"
    echo "   1) Automatic optimal server (Default)"
    echo "   2) List nearest servers and choose Server ID"
    echo "   3) Test with specific Server ID"
    echo "   4) Test with specific Server Host"
    echo "   5) View Speedtest History (/root/speedtest.log)"
    echo "   6) Reinstall / Update Official Ookla Speedtest CLI"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-6]: " speed_choice
    
    [[ "$speed_choice" == "0" ]] && { log_warn "Cancelled"; return 0; }
    
    case $speed_choice in
        1) 
            execute_speedtest \
                "Speedtest (Auto Optimal Server)" \
                "speedtest --accept-license --accept-gdpr" \
                "Automatic Optimal Server"
            ;;
        2) 
            log_info "Fetching nearest servers..."
            speedtest -L --accept-license --accept-gdpr
            echo
            read -rp "   Enter Server ID: " server_id
            if [[ -n "$server_id" ]]; then
                execute_speedtest \
                    "Speedtest (Server ID: $server_id)" \
                    "speedtest -s $server_id --accept-license --accept-gdpr" \
                    "Server ID: $server_id"
            fi
            ;;
        3)
            read -rp "   Enter Server ID: " server_id
            if [[ -n "$server_id" ]]; then
                execute_speedtest \
                    "Speedtest (Server ID: $server_id)" \
                    "speedtest -s $server_id --accept-license --accept-gdpr" \
                    "Server ID: $server_id"
            fi
            ;;
        4)
            read -rp "   Enter Server Host (e.g. speedtest.example.com:8080): " server_host
            if [[ -n "$server_host" ]]; then
                execute_speedtest \
                    "Speedtest (Host: $server_host)" \
                    "speedtest -o $server_host --accept-license --accept-gdpr" \
                    "Server Host: $server_host"
            fi
            ;;
        5)
            view_speedtest_history
            ;;
        6)
            install_ookla_speedtest
            ;;
        *) log_warn "Invalid choice"; return 1 ;;
    esac
}
