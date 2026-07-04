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
        
        echo "   11) Speedtest - Speedtest-cli (Country Selection)"
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

run_speedtest() {
    section_title "Running Speedtest (Ookla)"
    
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log_info "speedtest-cli not found. Installing..."
        if [[ "$SSE_OS_TYPE" == "debian" ]]; then
            pkg_update >/dev/null 2>&1 && pkg_install "speedtest-cli" >/dev/null 2>&1
        else
            pkg_update >/dev/null 2>&1 && pkg_install "speedtest" >/dev/null 2>&1
        fi
    fi
    
    echo "   Speedtest options:"
    echo "   1) Automatic server selection (interactive)"
    echo "   2) List servers and choose"
    echo "   3) Test download only"
    echo "   4) Test upload only"
    echo "   5) Share results"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-5]: " speed_choice
    
    [[ "$speed_choice" == "0" ]] && { log_warn "Cancelled"; return 1; }
    
    case $speed_choice in
        1) 
            run_generic_command \
                "Speedtest" \
                "interactive" \
                "speedtest-cli" \
                "Interactive network speed test" \
                "speedtest.net"
            ;;
        2) 
            log_info "Fetching server list..."
            speedtest-cli --list | head -20
            read -rp "   Enter server ID: " server_id
            if [[ -n "$server_id" ]]; then
                run_generic_command \
                    "Speedtest" \
                    "interactive" \
                    "speedtest-cli --server $server_id" \
                    "Interactive network speed test with selected server" \
                    "speedtest.net"
            fi
            ;;
        3)
            run_generic_command \
                "Speedtest (Download Only)" \
                "interactive" \
                "speedtest-cli --no-upload" \
                "Interactive download speed test" \
                "speedtest.net"
            ;;
        4)
            run_generic_command \
                "Speedtest (Upload Only)" \
                "interactive" \
                "speedtest-cli --no-download" \
                "Interactive upload speed test" \
                "speedtest.net"
            ;;
        5)
            run_generic_command \
                "Speedtest (with Sharing)" \
                "interactive" \
                "speedtest-cli --share" \
                "Interactive network speed test with result sharing" \
                "speedtest.net"
            ;;
        *) log_warn "Invalid choice"; return 1 ;;
    esac
}
