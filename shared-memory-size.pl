#!/usr/bin/env perl
# Time-stamp: <2012-09-04 20:00:08 JST, hirose31>

# 24時間本, pp201
# do as root
# shared-memory-size.pl $(pgrep httpd)

use strict;
use warnings;
use POSIX qw(strftime sysconf _SC_CLK_TCK);

my $HAS_SMAPS     = -e "/proc/self/smaps" ? 1 : 0;
my $CLOCK_TICK    = sysconf(_SC_CLK_TCK);
my $TIME_OF_BOOT  = time_of_boot(); # 起動したときの UNIX 時間
# fields of /proc/PID/stat
my %STAT_FIELD   = (
    0  => 'pid',
    1  => 'tcomm',
    2  => 'state',
    3  => 'ppid',
    4  => 'pgrp',
    5  => 'sid',
    # 6  => 'tty_nr',
    # 7  => 'tty_pgrp',
    # 8  => 'flags',
    # 9  => 'min_flt',
    # 10 => 'cmin_flt',
    # 11 => 'maj_flt',
    # 12 => 'cmaj_flt',
    # 13 => 'utime',
    # 14 => 'stime',
    # 15 => 'cutime',
    # 16 => 'cstime',
    17 => 'priority',
    18 => 'nice',
    19 => 'num_threads',
    # 20 => 'it_real_value',
    21 => 'start_time',
    # 22 => 'vsize',
    # 23 => 'rss',
    # 24 => 'rsslim',
    # 25 => 'start_code',
    # 26 => 'end_code',
    # 27 => 'start_stack',
    # 28 => 'esp',
    # 29 => 'eip',
    # 30 => 'pending',
    # 31 => 'blocked',
    # 32 => 'sigign',
    # 33 => 'sigcatch',
    # 34 => 'wchan',
    # 35 => '0',
    # 36 => '0',
    # 37 => 'exit_signal',
    # 38 => 'task_cpu',
    39 => 'rt_priority',
    # 40 => 'policy',
    41 => 'blkio_ticks',
    # 42 => 'gtime',
    # 43 => 'cgtime',
   );


@ARGV or die "usage $0 [pid ...]";

printf "%5s %7s %7s %7s %7s[KB]\n", qw(PID VSZ RSS PRIVATE SHARED);

for my $map (sort { $b->{rss} <=> $a->{rss} } grep $_, map {make_procinfo($_)} @ARGV) {

    printf("%5d %7d %7d %7d %7d (%3d%%)\n",
           $map->{pid},
           $map->{size},
           $map->{rss},
           $map->{private},
           $map->{shared},
           int((($map->{shared}) / $map->{rss}) * 100),
          );
}


sub make_procinfo {
    my $pid       = shift;
    my $proc_base = "/proc/$pid";
    my $procinfo  = {};
    my $buf;

    $procinfo->{pid} = $pid;

    ### custom
    $procinfo->{has_child} = 0;

    ### status
    # kernel threadはrssとかが取れないので0を入れておく。
    $procinfo->{size}    = $procinfo->{rss}    = 0;
    $procinfo->{private} = $procinfo->{shared} = 0;
    open my $status, '<', "$proc_base/status" or do {
        warn "failed to open $proc_base/status: $!";
        return;
    };
    while (<$status>) {
        if (/^Name:\s+(.+)/) {
            $procinfo->{name} = $1;
        } elsif (/^Uid:\s+(\d+)\s+(\d+)/) {
            $procinfo->{uid}   = $1;
            $procinfo->{user}  = username_of($1);
            $procinfo->{euid}  = $2;
            $procinfo->{euser} = username_of($2);
        } elsif (/^Gid:\s+(\d+)\s+(\d+)/) {
            $procinfo->{gid}    = $1;
            $procinfo->{group}  = groupname_of($1);
            $procinfo->{egid}   = $2;
            $procinfo->{egroup} = groupname_of($2);
        }
        # smaps がないマシンのために、rss はここでまず取っておく。
        elsif (/^VmSize:\s+(\d+)/) {
            $procinfo->{size} = $1; # KB
        } elsif (/^VmRSS:\s+(\d+)/) {
            $procinfo->{rss}  = $1; # KB
        }
    }
    close $status;

    ### cmdline
    open my $cmdline, '<', "$proc_base/cmdline" or do {
        warn "failed to open $proc_base/cmdline: $!";
        return;
    };
    if (defined($buf = <$cmdline>)) {
        $buf =~ s/[\0\a]/ /g;
    }
    # cmdline が空の場合は kernel thread とみなす。
    $procinfo->{cmdline} = $buf || '['.$procinfo->{name}.']';
    close $cmdline;

    ### stat
    open my $stat, '<', "$proc_base/stat" or do {
        warn "failed to open $proc_base/stat: $!";
        return;
    };
    $buf = <$stat>;
    defined $buf or die $!;
    my @elm = split /\s+/, $buf;
    while (my($k,$v) = each %STAT_FIELD) {
        $procinfo->{$v} = $elm[$k];
    }
    close $stat;

    $procinfo->{start_unix_time} = convert_into_start_unix_time($procinfo->{start_time});

    ### smaps
    if ($HAS_SMAPS) {
        my $smap = get_smaps($pid) or return;
        if ($smap->{unnamed}{rss}) {
            $procinfo->{size}    = $smap->{unnamed}{size};
            $procinfo->{rss}     = $smap->{unnamed}{rss};
            $procinfo->{private} = ($smap->{unnamed}{private_dirty} + $smap->{unnamed}{private_clean});
            $procinfo->{shared}  = ($smap->{unnamed}{shared_dirty}  + $smap->{unnamed}{shared_clean});
        } else {
            warn "skip this process: cannot read smaps. maybe you have no permission. [pid=$pid euser=$procinfo->{euser} cmdline=$procinfo->{cmdline}]";
            return;
        }
    }

    return $procinfo;
}

# Linux::Smaps と違い、
# [heap] [stack] [vdso] [vsyscall]
# は named じゃなくて unnamed に入れます。
sub get_smaps {
    my $pid = shift;
    my $smaps;
    my $name;

    open my $fh, '<', "/proc/$pid/smaps" or return;
    while (<$fh>) {
        if (substr($_, -3) eq "kB\n") {
            my($field, $value) = split /:?\s+/, $_;
            $smaps->{$name}{lc($field)} += $value;

        } elsif (/^(?:[\da-fA-F]+-[\da-fA-F]+)\s/o) {
            my $n = (split /\s+/, $_)[5];
            if ($n && substr($n, 0, 1) ne '[') {
                $name = 'named';
            } else {
                $name = 'unnamed';
            }
        }
    }
    close $fh;

    for my $f (keys %{ $smaps->{named} }) {
        $smaps->{unnamed}{$f} = 0 if ! exists $smaps->{unnamed}{$f};
        $smaps->{all}{$f} = $smaps->{named}{$f} + $smaps->{unnamed}{$f};
    }

    return $smaps;
}

# /proc/PID/stat の start_time を受けて、プロセスが起動した時刻の
# UNIX 時間を返す。
sub convert_into_start_unix_time {
    my $start_time_jiffies = shift;
    return int( $TIME_OF_BOOT + ($start_time_jiffies / $CLOCK_TICK) );
}

sub time_of_boot {
    open my $u, '<', '/proc/uptime' or die $!;
    my $buf = <$u>;
    my($seconds_since_boot) = (split /\s+/, $buf);
    close $u;
    return time() - $seconds_since_boot;
}

sub username_of {
    my $uid = shift;
    getpwuid($uid) || undef
}

sub groupname_of {
    my $gid = shift;
    getgrgid($gid) || undef
}
