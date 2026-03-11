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
backup_enabled=true
restore_mode=false

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

# Backup original MP4 file
backup_mp4() {
    local input_file="$1"
    local backup_file="${input_file}.bak"
    
    if [ "$backup_enabled" = false ]; then
        return 0
    fi
    
    if [ -f "$backup_file" ]; then
        log_warning "Backup file already exists, skipping backup: $backup_file"
        return 1
    fi
    
    if [ "$dry_run" = true ]; then
        log_info "[DRY-RUN] will backup: mv \"$input_file\" \"$backup_file\""
        return 0
    fi
    
    if mv "$input_file" "$backup_file"; then
        log_success "Backup created: $backup_file"
        return 0
    else
        log_error "Failed to create backup: $input_file"
        return 1
    fi
}

# Restore backup files
restore_backup() {
    local backup_file="$1"
    local original_file="${backup_file%.bak}"
    local webm_file="${original_file%.mp4}.webm"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    if [ -f "$original_file" ]; then
        log_warning "Original file already exists, skipping restore: $original_file"
        return 2
    fi
    
    # Delete corresponding webm file if it exists
    if [ -f "$webm_file" ]; then
        if [ "$dry_run" = true ]; then
            log_info "[DRY-RUN] will delete webm file: rm \"$webm_file\""
        else
            if rm "$webm_file"; then
                log_success "Deleted webm file: $webm_file"
            else
                log_error "Failed to delete webm file: $webm_file"
                return 1
            fi
        fi
    else
        log_info "No corresponding webm file found: $webm_file"
    fi
    
    if [ "$dry_run" = true ]; then
        log_info "[DRY-RUN] will restore: mv \"$backup_file\" \"$original_file\""
        return 0
    fi
    
    if mv "$backup_file" "$original_file"; then
        log_success "Restored: $original_file"
        return 0
    else
        log_error "Failed to restore: $backup_file"
        return 1
    fi
}

# Find and restore all backup files
find_and_restore_backups() {
    log_info "Searching for backup files..."
    
    local backup_files=()
    mapfile -t backup_files < <(find "MaiCharts" -name "*.mp4.bak" -type f 2>/dev/null)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        log_warning "No backup files found"
        return 1
    fi
    
    log_info "Found ${#backup_files[@]} backup files:"
    for file in "${backup_files[@]}"; do
        echo "  - $file"
    done
    
    local total_files=${#backup_files[@]}
    local success_count=0
    local fail_count=0
    local skip_count=0
    
    log_info "Starting restore ($total_files files)..."
    echo "========================================"
    
    for ((i=0; i<total_files; i++)); do
        local backup_file="${backup_files[$i]}"
        
        echo -e "\n[File $((i+1))/$total_files]"
        
        local result
        set +e
        restore_backup "$backup_file"
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
    log_info "Restore completed."
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
    
    return 0
}

# Get video bitrate from source file
get_video_bitrate() {
    local input_file="$1"
    local bitrate
    
    bitrate=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$input_file" 2>/dev/null)
    
    if [ -z "$bitrate" ] || [ "$bitrate" = "N/A" ] || [ "$bitrate" = "0" ]; then
        log_warning "Cannot get video bitrate from $input_file, using default"
        echo ""
        return 1
    fi
    
    echo "$bitrate"
    return 0
}

# Get audio bitrate from source file
get_audio_bitrate() {
    local input_file="$1"
    local bitrate
    
    bitrate=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$input_file" 2>/dev/null)
    
    if [ -z "$bitrate" ] || [ "$bitrate" = "N/A" ] || [ "$bitrate" = "0" ]; then
        log_warning "Cannot get audio bitrate from $input_file, using default"
        echo ""
        return 1
    fi
    
    echo "$bitrate"
    return 0
}

# Transcoding MP4 to WebM(VP8) with source bitrate preservation
transcode_to_webm() {
    local input_file="$1"
    local output_file="${input_file%.mp4}.webm"
    
    log_info "Transcoding: $(basename "$input_file") -> $(basename "$output_file")"
    
    # Checking exists
    if [ -f "$output_file" ]; then
        log_warning "The output file already exists, skipping: $output_file"
        return 2
    fi
    
    # Get source bitrates
    local video_bitrate=""
    local audio_bitrate=""
    local ffmpeg_cmd="ffmpeg -i \"$input_file\""
    
    if video_bitrate=$(get_video_bitrate "$input_file"); then
        ffmpeg_cmd="$ffmpeg_cmd -b:v ${video_bitrate}"
        log_info "Using source video bitrate: $((video_bitrate / 1000)) kbps"
    else
        ffmpeg_cmd="$ffmpeg_cmd -b:v 1M"  # Default 1 Mbps
        log_info "Using default video bitrate: 1 Mbps"
    fi
    
    if audio_bitrate=$(get_audio_bitrate "$input_file"); then
        ffmpeg_cmd="$ffmpeg_cmd -b:a ${audio_bitrate}"
        log_info "Using source audio bitrate: $((audio_bitrate / 1000)) kbps"
    else
        ffmpeg_cmd="$ffmpeg_cmd -b:a 128k"  # Default 128 kbps
        log_info "Using default audio bitrate: 128 kbps"
    fi
    
    # Complete ffmpeg command with quality optimization for VP8
    # -quality good: better encoding quality
    # -cpu-used 0: best quality (slowest)
    # -qmin 10 -qmax 42: quantization parameter range
    # -threads 0: auto-detect number of threads
    ffmpeg_cmd="$ffmpeg_cmd -c:v libvpx -quality good -cpu-used 0 -qmin 10 -qmax 42 -threads 0 -c:a libvorbis -f webm -y \"$output_file\""
    
    # dry-run
    if [ "$dry_run" = true ]; then
        log_info "[DRY-RUN] will run: $ffmpeg_cmd"
        if [ "$backup_enabled" = true ]; then
            log_info "[DRY-RUN] will backup: mv \"$input_file\" \"${input_file}.bak\""
        fi
        return 0
    fi
    
    if eval "$ffmpeg_cmd" 2>&1 | tee /tmp/ffmpeg_output.log; then
        log_success "Transcode success: $output_file"
        
        # Backup original file after successful transcode
        backup_mp4 "$input_file"
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
    
    # Check if we're in restore mode
    if [ "$restore_mode" = true ]; then
        log_info "RESTORE MODE: Restoring backup files"
        find_and_restore_backups
        return 0
    fi
    
    # Normal transcode mode
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
    echo "  -r, --restore  Restore backup files (.mp4.bak -> .mp4) and delete corresponding .webm files"
    echo "  --no-backup    Disable backup of original files"
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
            -r|--restore)
                restore_mode=true
                shift
                ;;
            --no-backup)
                backup_enabled=false
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
