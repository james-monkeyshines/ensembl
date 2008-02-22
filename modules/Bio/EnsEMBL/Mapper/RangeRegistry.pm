#
# Ensembl module for Bio::EnsEMBL::Mapper::RangeRegistry
#
#
# You may distribute this module under the same terms as perl itself

=head1 NAME

Bio::EnsEMBL::Mapper::RangeRegistry

=head1 SYNOPSIS

   use Bio::EnsEMBL::Mapper::RangeRegistry;

   $rr = Bio::EnsEMBL::Mapper::RangeRegistry->new();

   #get a fixed width chunk around the range of intereset
   #this will be used if any registration is actually necessary
   $chunk_start = ($start >> 20) << 20 + 1;
   $chunk_end   = (($end >> 20) + 1) << 20;

  #check if any registration is necessary for the range.
  #if it is register a large chunked area instead and return a listref
  #of unregistered areas that need to be loaded.
  if($pairs=$rr->check_and_register($id,$start,$end,$chunk_start,$chunk_end)) {
    foreach my $pair (@$pairs) {
      my ($pair_start, $pair_end) = @$pair;
      #fetch mappings for these regions from the assembly table and load them
      #into the mapper
      ...
    }
  } else {
    #the range ($start - $end) is already registered
    ...
  }


  #check if any registration is necessary
  #if it is register the region and return a listref of pairs that
  #need to be loaded.
  if($pairs = $rr->check_and_register($id, $start,$end)) {
  }


=head1 DESCRIPTION

This module maintains an internal list of registered regions and is used to
quickly ascertain if and what regions of a provided range need registration.

=head1 AUTHOR - Graham McVicker

=head1 CONTACT

This modules is part of the Ensembl project http://www.ensembl.org

Questions can be posted to the ensembl-dev mailing list:
ensembl-dev@ebi.ac.uk

=cut

use strict;

package Bio::EnsEMBL::Mapper::RangeRegistry;

use Bio::EnsEMBL::Utils::Exception qw(throw);
use integer;

=head2 new

  Arg [1]    : none
  Example    : my $rr = Bio::EnsEMBL::Mapper::RangeRegistry->new();
  Description: Creates a new RangeRegistry object
  Returntype : Bio::EnsEMBL::Mapper::RangeRegistry
  Exceptions : none
  Caller     : AssemblyMapperAdaptor
  Status     : Stable

=cut

sub new {
  my ($proto) = @_;

  my $class = ref($proto) || $proto;

  return bless( { 'registry' => {} }, $class );
}

sub flush {
  my ($self) = @_;
  $self->{'registry'} = {};
}

=head2 check_and_register

  Arg [1]    : string $id
               The id of the range to be checked/registered (e.g. a sequenceid)
  Arg [2]    : int $start
               The start of the range to be checked
  Arg [3]    : int $end
               The end of the range to be checked
  Arg [4]    : (optional) int $rstart
               The start of the range to be registered
               if the checked range was not fully registered
  Arg [5]    : (optional) int $rend
               The end of the range to be registerd
               if the checked range was not fully registered
  Example    : $ranges=$rr->check_and_register('X',500,600, 1,1_000_000));
  Description: Checks the range registry to see if the entire range
               denoted by ($id : $start-$end) is already registered.  If
               it already is, then undef is returned.  If it is not then
               the range specified by $rstart and $rend is registered, and
               a list of regions that were required to completely register
               $rstart-$rend is returned.  If $rstart and $rend are not
               defined they default to $start and $end respectively.

               The reason there is a single call to do both the checking and
               registering is to reduce the overhead. Much of the work to
               check if a range is registered is the same as registering a
               region around that range.
  Returntype : undef or listref of [start,end] range pairs
  Exceptions : throw if rstart is greater than start
               throw if rend is less than end
               throw if end is less than start
               throw if id, start, or end are not defined
  Caller     : AssemblyMapperAdaptor
  Status     : Stable

=cut

#"constants"
my $START = 0;
my $END   = 1;

sub check_and_register {
  my ( $self, $id, $start, $end, $rstart, $rend ) = @_;

  $rstart = $start if ( !defined($rstart) );
  $rend   = $end   if ( !defined($rend) );

  #
  # Sanity checks
  #
  if ( !defined($id) || !defined($start) || !defined($end) ) {
    throw("ID, start, end arguments are required");
  }

  if ( $start > $end ) {
    throw("start argument must be less than end argument");
  }

  if ( $rstart > $rend ) {
    throw(
      "rend [$rstart] argument must be less than rend [$rend]  argument"
    );
  }

  if ( $rstart > $start ) {
    throw("rstart must be less than or equal to start");
  }

  if ( $rend < $end ) {
    throw("rend must be greater than or equal to end");
  }

  my $reg = $self->{'registry'};
  my $list = $reg->{$id} ||= [];

  my @gap_pairs;

  my $len = scalar(@$list);

  if ( $len == 0 ) {
    # this is the first request for this id, return a gap pair for the
    # entire range and register it as seen
    $list->[0] = [ $rstart, $rend ];
    return [ [ $rstart, $rend ] ];
  }

  #####
  # loop through the list of existing ranges recording any "gaps" where
  # the existing range does not cover part of the requested range
  #

  my $start_idx = 0;
  my $end_idx   = $#$list;
  my ( $mid_idx, $range );

  # binary search the relevant pairs
  # helps if the list is big
  while ( ( $end_idx - $start_idx ) > 1 ) {
    $mid_idx = ( $start_idx + $end_idx ) >> 1;
    $range   = $list->[$mid_idx];

    if ( $range->[1] < $rstart ) {
      $start_idx = $mid_idx;
    } else {
      $end_idx = $mid_idx;
    }
  }

  my ( $gap_start, $gap_end, $r_idx, $rstart_idx, $rend_idx );
  $gap_start = $rstart;

  for ( my $CUR = $start_idx ; $CUR < $len ; $CUR++ ) {
    my ( $pstart, $pend ) = @{ $list->[$CUR] };

    # no work needs to be done at all if we find a range pair that
    # entirely overlaps the requested region
    if ( $pstart <= $start && $pend >= $end ) {
      return undef;
    }

    # find adjacent or overlapping regions already registered
    if ( $pend >= ( $rstart - 1 ) && $pstart <= ( $rend + 1 ) ) {
      if ( !defined($rstart_idx) ) {
        $rstart_idx = $CUR;
      }
      $rend_idx = $CUR;
    }

    if ( $pstart > $rstart ) {
      $gap_end = ( $rend < $pstart ) ? $rend : $pstart - 1;
      push @gap_pairs, [ $gap_start, $gap_end ];
    }

    $gap_start = ( $rstart > $pend ) ? $rstart : $pend + 1;

    #    if($pstart > $rend && !defined($r_idx)) {
    if ( $pend >= $rend && !defined($r_idx) ) {
      $r_idx = $CUR;
      last;
    }
  } ## end for ( my $CUR = $start_idx...

  # do we have to make another gap?
  if ( $gap_start <= $rend ) {
    push @gap_pairs, [ $gap_start, $rend ];
  }

  #
  # Merge the new range into the registered list
  #
  if ( defined($rstart_idx) ) {
    my ( $new_start, $new_end );

    if ( $rstart < $list->[$rstart_idx]->[0] ) {
      $new_start = $rstart;
    } else {
      $new_start = $list->[$rstart_idx]->[0];
    }

    if ( $rend > $list->[$rend_idx]->[1] ) {
      $new_end = $rend;
    } else {
      $new_end = $list->[$rend_idx]->[1];
    }

    splice( @$list, $rstart_idx,
            $rend_idx - $rstart_idx + 1,
            [ $new_start, $new_end ] );

  } elsif ( defined($r_idx) ) {
    splice( @$list, $r_idx, 0, [ $rstart, $rend ] );
  } else {
    push( @$list, [ $rstart, $rend ] );
  }

  return \@gap_pairs;
} ## end sub check_and_register

# overlap size is just added to make RangeRegistry generally more useful

=head2 overlap_size

  Arg [1]    : string $id
  Arg [2]    : int $start
  Arg [1]    : int $end
  Example    : my $overlap_size = $rr->( "chr1", 1, 100_000_000 )
  Description: finds out how many bases of the given range are registered
  Returntype : int
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub overlap_size {
  my ( $self, $id, $start, $end ) = @_;

  my $overlap = 0;

  if ( $start > $end ) { return 0 }

  my $reg = $self->{'registry'};
  my $list = $reg->{$id} ||= [];

  my $len = scalar(@$list);

  if ( $len == 0 ) {
    # this is the first request for this id, return a gap pair for the
    # entire range and register it as seen
    return 0;
  }

  #####
  # loop through the list of existing ranges recording any "gaps" where
  # the existing range does not cover part of the requested range
  #

  my $start_idx = 0;
  my $end_idx   = $#$list;
  my ( $mid_idx, $range );

  # binary search the relevant pairs
  # helps if the list is big
  while ( ( $end_idx - $start_idx ) > 1 ) {
    $mid_idx = ( $start_idx + $end_idx ) >> 1;
    $range   = $list->[$mid_idx];
    if ( $range->[1] < $start ) {
      $start_idx = $mid_idx;
    } else {
      $end_idx = $mid_idx;
    }
  }

  for ( my $CUR = $start_idx ; $CUR < $len ; $CUR++ ) {
    my ( $pstart, $pend ) = @{ $list->[$CUR] };

    if ( $pstart > $end ) {
      # No more interesting ranges here.
      last;
    }

    # no work needs to be done at all if we find a range pair that
    # entirely overlaps the requested region
    if ( $pstart <= $start && $pend >= $end ) {
      $overlap = $end - $start + 1;
      last;
    }

    my $mstart = ( $start < $pstart ? $pstart : $start );
    my $mend   = ( $end < $pend     ? $end    : $pend );

    if ( $mend - $mstart >= 0 ) {
      $overlap += ( $mend - $mstart + 1 );
    }
  }

  return $overlap;
} ## end sub overlap_size


# low level function to access the ranges
# only use for read access

sub get_ranges {
  my ( $self, $id ) = @_;

  return $self->{'registry'}->{$id};
}

1;

