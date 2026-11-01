#ifndef C_LYRICS_ENGINE_H
#define C_LYRICS_ENGINE_H

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double time_sec;     // Timestamp in seconds (-1 for plain unsynced)
    int text_offset;     // Byte offset in the source UTF-8 string
    int text_length;     // Length of line text in bytes
} CLyricEntry;

/**
 * Fast binary search to find the active lyric index given current playback time and lead offset.
 * Runs in O(log N) time with zero dynamic memory allocation.
 *
 * @param timestamps Array of line timestamps in ascending order
 * @param count Number of lines in the timestamps array
 * @param current_time Current playhead time in seconds (from AVPlayer / audio engine)
 * @param lead_offset Anticipation offset in seconds (e.g. 0.35s to account for audio output buffer latency)
 * @return Index of the active line (0 to count - 1), or -1 if before the first line
 */
int c_lyrics_find_active_index(const double *timestamps, int count, double current_time, double lead_offset);

/**
 * Calculates progress percentage (0.0 to 1.0) of the current active line.
 */
double c_lyrics_get_line_progress(const double *timestamps, int count, int active_index, double current_time, double lead_offset);

/**
 * High-speed LRC parser in C.
 * Scans byte-by-byte for [mm:ss.xx] and fills entries without regex overhead.
 *
 * @param lrc_utf8 Pointer to null-terminated UTF-8 string of LRC content
 * @param entries_out Pre-allocated array of CLyricEntry
 * @param max_entries Capacity of entries_out
 * @return Number of lines parsed
 */
int c_lyrics_parse_lrc(const char *lrc_utf8, CLyricEntry *entries_out, int max_entries);

#ifdef __cplusplus
}
#endif

#endif /* C_LYRICS_ENGINE_H */
