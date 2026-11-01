#include "include/CLyricsEngine.h"
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

int c_lyrics_find_active_index(const double *timestamps, int count, double current_time, double lead_offset) {
    if (!timestamps || count <= 0) {
        return -1;
    }

    double target_time = current_time + lead_offset;

    // If target time is before the very first timestamp, nothing is active yet
    if (target_time < timestamps[0]) {
        return -1;
    }

    int low = 0;
    int high = count - 1;
    int best = -1;

    // Standard binary search for the largest index where timestamps[index] <= target_time
    while (low <= high) {
        int mid = low + ((high - low) >> 1);
        if (timestamps[mid] <= target_time) {
            best = mid;
            low = mid + 1; // Try to search further to find the latest valid line
        } else {
            high = mid - 1;
        }
    }

    return best;
}

double c_lyrics_get_line_progress(const double *timestamps, int count, int active_index, double current_time, double lead_offset) {
    if (!timestamps || active_index < 0 || active_index >= count) {
        return 0.0;
    }

    double t = current_time + lead_offset;
    double start = timestamps[active_index];
    double end;

    if (active_index + 1 < count) {
        end = timestamps[active_index + 1];
    } else {
        end = start + 4.0; // fallback estimated duration for last line
    }

    if (end <= start) {
        return 1.0;
    }

    double progress = (t - start) / (end - start);
    if (progress < 0.0) progress = 0.0;
    if (progress > 1.0) progress = 1.0;
    return progress;
}

static bool parse_lrc_tag(const char *p, double *out_time_sec, int *out_tag_len) {
    // Expects: [mm:ss.xx] or [mm:ss] or [mm:ss:xx]
    if (*p != '[') return false;
    const char *start = p + 1;
    const char *colon = strchr(start, ':');
    if (!colon) return false;

    // Parse minutes
    char *endptr = NULL;
    long minutes = strtol(start, &endptr, 10);
    if (endptr != colon || minutes < 0) return false;

    // Parse seconds (can have decimals like .25 or :25)
    const char *sec_start = colon + 1;
    double seconds = strtod(sec_start, &endptr);
    if (endptr == sec_start) return false;

    const char *close_bracket = strchr(endptr, ']');
    if (!close_bracket) return false;

    *out_time_sec = (double)minutes * 60.0 + seconds;
    *out_tag_len = (int)(close_bracket - p + 1);
    return true;
}

int c_lyrics_parse_lrc(const char *lrc_utf8, CLyricEntry *entries_out, int max_entries) {
    if (!lrc_utf8 || !entries_out || max_entries <= 0) {
        return 0;
    }

    int entry_count = 0;
    const char *p = lrc_utf8;
    const char *base = lrc_utf8;

    while (*p && entry_count < max_entries) {
        // Skip leading whitespace / newlines
        while (*p == '\r' || *p == '\n') p++;
        if (!*p) break;

        const char *line_start = p;
        double line_time = -1.0;
        int tag_len = 0;

        // Check if line starts with a timestamp [mm:ss.xx]
        if (*p == '[' && parse_lrc_tag(p, &line_time, &tag_len)) {
            p += tag_len;
        }

        // Skip whitespace after tag
        while (*p == ' ' || *p == '\t') p++;

        int text_offset = (int)(p - base);
        
        // Find end of current line
        const char *line_end = p;
        while (*line_end && *line_end != '\r' && *line_end != '\n') {
            line_end++;
        }

        // Trim trailing whitespace from line
        const char *trimmed_end = line_end;
        while (trimmed_end > p && (*(trimmed_end - 1) == ' ' || *(trimmed_end - 1) == '\t')) {
            trimmed_end--;
        }

        int text_length = (int)(trimmed_end - p);

        // Store entry
        entries_out[entry_count].time_sec = line_time;
        entries_out[entry_count].text_offset = text_offset;
        entries_out[entry_count].text_length = text_length;
        entry_count++;

        p = line_end;
    }

    return entry_count;
}
