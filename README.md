# shared-memory-size.pl

## NAME

__shared-memory-size.pl__ - display shared memory size by CoW

## SYNOPSIS

__shared-memory-size.pl__ PID [PID ...]

    # shared-memory-size.pl $(pidof httpd)
    
      PID     VSZ     RSS PRIVATE  SHARED[KB]
     8170    2344    1628     424    1204 ( 73%)
    19038    2100    1492     376    1116 ( 74%)
    16281    2100    1492     376    1116 ( 74%)
    11034    2100    1492     376    1116 ( 74%)
    18206    2100    1484     368    1116 ( 75%)
    16555    2344    1476     116    1360 ( 92%)
    11445    2344    1476     116    1360 ( 92%)
    16175    2344    1428      68    1360 ( 95%)
    19706    1968    1372     256    1116 ( 81%)
    19707    1968    1368     252    1116 ( 81%)
    16176    1968    1292     176    1116 ( 86%)

# DESCRIPTION

display shared memory size by CoW

# AUTHOR

HIROSE, Masaaki <hirose31 _at_ gmail.com>

# COPYRIGHT & LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

