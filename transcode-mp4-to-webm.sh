#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Env
dry_run=false
search_dir="MaiCharts"
declare -a mp4_files

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Checking ffmpeg
check_dependencies() {
    log_info "Checking ffmpeg..."
    
    if ! command -v ffmpeg &> /dev/null; then
        log_error "ffmpeg isn't installed"
        exit 1
    fi
    
    log_success "ffmpeg installed: $(ffmpeg -version | head -1)"
}

# Searching MP4 videos.
find_mp4_files() {
    log_info "Searching MP4 videos..."
    
    mapfile -t mp4_files < <(find "MaiCharts" -name "*.mp4" -type f 2>/dev/null)
    
    if [ ${#mp4_files[@]} -eq 0 ]; then
        log_warning "No files"
        return 1
    fi
    
    log_info "Found ${#mp4_files[@]} files:"
    for file in "${mp4_files[@]}"; do
        echo "  - $file"
    done
    
    return 0
}

# Transcoding MP4 to WebM(VP8)
transcode_to_webm() {
    local input_file="$1"
    local output_file="${input_file%.mp4}.webm"
    
    log_info "Transcoding: $(basename "$input_file") -> $(basename "$output_file")"
    
    # Checking exists
    if [ -f "$output_file" ]; then
        log_warning "The output file already exists, skipping: $output_file"
        return 2
    fi
    
    # dry-run
    if [ "$dry_run" = true ]; then
        log_info "[DRY-RUN] will run: ffmpeg -i \"$input_file\" -c:v libvpx -c:a libvorbis -f webm -y \"$output_file\""
        return 0
    fi
    
    if ffmpeg -i "$input_file" \
        -c:v libvpx \
        -c:a libvorbis \
        -f webm \
        -y "$output_file" 2>&1 | tee /tmp/ffmpeg_output.log; then
        log_success "Transcode success: $output_file"
        return 0
    else
        log_error "Transcode failed: $input_file"
        if [ -f /tmp/ffmpeg_output.log ]; then
            log_error "FFmpeg error:"
            tail -20 /tmp/ffmpeg_output.log | while read -r line; do
                echo "  $line"
            done
        fi
        return 1
    fi
}

main() {
    log_info "Searching: MaiCharts"
    
    if [ "$dry_run" = true ]; then
        log_warning "DRY-RUN Mode: Only display the actions to be performed."
    fi
    
    check_dependencies

    if ! find_mp4_files; then
        log_error "Not found any supported files. Aborting..."
        exit 1
    fi
    
    # Statistical variable
    local total_files=${#mp4_files[@]}
    local success_count=0
    local fail_count=0
    local skip_count=0
    
    log_info "Starting transcode ($total_files files)..."
    echo "========================================"
    
    for ((i=0; i<total_files; i++)); do
        local input_file="${mp4_files[$i]}"
        
        echo -e "\n[File $((i+1))/$total_files]"
        
        local result
        # Temporarily disable set -e, as transcode_to_webm may return a non-zero exit code (skipped or failed).
        set +e
        transcode_to_webm "$input_file"
        result=$?
        set -e
        
        case $result in
            0) success_count=$((success_count + 1)) ;;
            1) fail_count=$((fail_count + 1)) ;;
            2) skip_count=$((skip_count + 1)) ;;
        esac
        
        echo "In progress: $((i+1))/$total_files | Success: $success_count | Fail: $fail_count | Skip: $skip_count"
    done
    
    echo "========================================"
    log_info "Transcoding completed."
    log_info "Total: $total_files files"
    
    if [ $success_count -gt 0 ]; then
        log_success "Success: $success_count files"
    fi
    
    if [ $fail_count -gt 0 ]; then
        log_error "Fail: $fail_count files"
    fi
    
    if [ $skip_count -gt 0 ]; then
        log_warning "Skip: $skip_count files"
    fi
    
    if [ "$dry_run" = false ] && [ $success_count -gt 0 ]; then
        log_info "WebM files:"
        find "MaiCharts" -name "*.webm" -type f 2>/dev/null | while read -r webm_file; do
            echo "  - $webm_file"
        done
    fi
    
    if [ -f /tmp/ffmpeg_output.log ]; then
        rm -f /tmp/ffmpeg_output.log
    fi
}

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "options:"
    echo "  -h, --help     Show this help"
    echo "  --dry-run      Only display the files found; no transcode."
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi
