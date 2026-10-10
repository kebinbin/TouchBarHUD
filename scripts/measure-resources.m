#import <Foundation/Foundation.h>
#import <libproc.h>
#import <sys/resource.h>
#import <time.h>
#import <stdlib.h>
#import <stdio.h>

static BOOL ReadUsage(pid_t pid, struct rusage_info_v2 *usage) {
    return proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)usage) == 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "Usage: measure-resources PID SECONDS\n");
            return 64;
        }
        char *pidEnd, *secondsEnd;
        long processID = strtol(argv[1], &pidEnd, 10), seconds = strtol(argv[2], &secondsEnd, 10);
        if (*pidEnd || *secondsEnd || processID <= 0 || processID > INT_MAX || seconds < 1 || seconds > 3600) {
            fprintf(stderr, "Expected a positive PID and 1–3600 seconds.\n");
            return 64;
        }
        struct rusage_info_v2 initial = {0}, current = {0};
        if (!ReadUsage((pid_t)processID, &initial)) { perror("proc_pid_rusage"); return 1; }
        uint64_t minimum = initial.ri_phys_footprint, maximum = minimum;
        NSMutableArray<NSNumber *> *samples = [NSMutableArray arrayWithObject:@(minimum)];
        NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
        for (long i = 0; i < seconds; i++) {
            struct timespec delay = {1, 0};
            while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
            if (!ReadUsage((pid_t)processID, &current)) { perror("proc_pid_rusage"); return 1; }
            minimum = MIN(minimum, current.ri_phys_footprint);
            maximum = MAX(maximum, current.ri_phys_footprint);
            [samples addObject:@(current.ri_phys_footprint)];
        }
        NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - start;
        double cpuSeconds = ((current.ri_user_time - initial.ri_user_time) +
                             (current.ri_system_time - initial.ri_system_time)) / 1e9;
        double mib = 1024.0 * 1024.0;
        NSDictionary *result = @{
            @"pid": @(processID), @"sample_seconds": @(duration),
            @"cpu_percent_one_core": @(cpuSeconds / duration * 100),
            @"physical_footprint_start_mib": @(initial.ri_phys_footprint / mib),
            @"physical_footprint_end_mib": @(current.ri_phys_footprint / mib),
            @"physical_footprint_min_mib": @(minimum / mib),
            @"physical_footprint_max_mib": @(maximum / mib),
            @"interrupt_wakeups_per_second": @((current.ri_interrupt_wkups - initial.ri_interrupt_wkups) / duration),
            @"package_idle_wakeups_per_second": @((current.ri_pkg_idle_wkups - initial.ri_pkg_idle_wkups) / duration),
            @"disk_read_bytes": @(current.ri_diskio_bytesread - initial.ri_diskio_bytesread),
            @"disk_written_bytes": @(current.ri_diskio_byteswritten - initial.ri_diskio_byteswritten),
            @"footprint_samples_bytes": samples};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        putchar('\n');
    }
    return 0;
}
