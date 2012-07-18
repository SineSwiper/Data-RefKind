package Data::Refkind;

=head1 NAME

Data::Refkind - Run a method or subroutine based on an extended reftype of a variable

=cut

use sanity;
use Scalar::Util qw/blessed looks_like_number reftype/;
use List::AllUtils qw/first/;

# Exporter stuff
use parent 'Exporter';
our %EXPORT_TAGS = (
   'util'   => [ qw(refkind try_refkind switch_refkind) ],
   'method' => [ qw(method_for_refkind call_method_for_refkind) ],
   'sub'    => [ qw(   sub_for_refkind    call_sub_for_refkind) ],
);
$EXPORT_TAGS{'all'} = [ map { @{ $EXPORT_TAGS{$_} } } keys %EXPORT_TAGS ];

our @EXPORT_OK = @{ $EXPORT_TAGS{'all'} };
our @EXPORT    = qw(switch_refkind);

=head1 SYNOPSIS

   use Data::Rekfind;  # switch_refkind exported by default
   
   switch_refkind($v, {

      ARRAYREF => sub {
         # do stuff
      },
      ARRAYREFREF => sub {
         # do other stuff
      },
      HASHREF => sub {
         # do something else
      },
      'DateTime::Duration' => sub {
         # also works for classes
      }
      NONREF => sub {
         # and other 'superclasses'
      },
      DEFAULT => sub {
         # if all else fails...
      },

   });
   
   use Data::Rekfind qw(:method :sub);

   # returns "$prefix_ARRAYREF", or "$prefix_NONREF", 
   # or "$prefix_DateTime__Duration", etc.
   my $method = method_for_refkind($self, $prefix, $v);
   my $sub    = sub_for_refkind($prefix, $v);
   
   # calls $self->$method(@args)
   call_method_for_refkind($self, $prefix, $v, @args);

   # calls &$sub(@args)
   call_sub_for_refkind($prefix, $v, @args);
   
=head1 DESCRIPTION

Do you find yourself dealing with a bunch of different types of Perl data?  This
module makes it easier to parse through that data by dispatching to different subs/methods
(anonymous or otherwise), based on an extended reftype.  This "refkind" looks a few
different properties of the variable to figure out exactly what type of data it is.

See L</refkind> and L</try_refkind> for more details on what refkind types are available.

=head1 SUBROUTINES

=head2 refkind

=over

=item Exporter Tag: :util

=item Arguments: $data

=item Return Value: ($class, $scalar_type, $ext_reftype)

=back

Given variable C<$data>, report back its refkind.  You actually don't need this sub,
but you should understand what it returns.

As you can see, a refkind is more than a single string.  It's three variables that
describe its parts:

B<C<$class>> = The class name, or undef if C<$data> is not blessed.

B<C<$scalar_type>> = Either C<NUMBER> or C<STRING>, depending on the value of L<looks_like_number|Scalar::Util/looks_like_number>,
or undef if C<$data> is not a C<SCALAR>.

B<C<$ext_reftype>> = An extended form of L<reftype|Scalar::Util/reftype>, which also
includes C<SCALAR> and C<UNDEF>.

Furthermore, the latter two parts are also subject to ref/glob dereferencing.  These
ref/glob types are appended to the main types.  For example:

   # if $data =
   \"45"              # NUMBERREF,    SCALARREF
   \\"45"             # NUMBERREFREF, SCALARREFREF
   *$str              # STRINGGLOB,   SCALARGLOB
   \[ $j, $k ]        # ARRAYREFREF
   \*\[ $j, $k ]      # ARRAYREFGLOBREF
   \\\\\[ $j, $k ]    # spam spam spam egg and spam spam spam baked beans spam...

NOTE: C<UNDEF> isn't subject to this rule.  A undef buried in refs will be a C<SCALARREF> of
some sort.

Also, any reftype that isn't a C<SCALAR> or C<UNDEF> will I<start> with C<REF> appended to it.
Thus, there is no such thing as a C<ARRAY> or C<HASH> or C<Regexp>.  These are instead
C<ARRAYREF>, C<HASHREF>, and C<RegexpREF>, respectively.

=cut

sub refkind {
   my ($data) = @_;
   my $class = blessed $data;
   my $ref   = reftype $data;

   return (undef, undef, 'UNDEF') unless defined $data;

   my $refsteps = $ref ? 'REF' : '';
   while ($ref =~ /REF|GLOB/) {
      if    ($ref eq 'REF') {
         $data = $$data;
         $ref = reftype $data;
         $refsteps .= 'REF' if $ref;
      }
      elsif ($ref eq 'GLOB') {
         foreach my $t (qw(Regexp VSTRING IO FORMAT LVALUE GLOB REF CODE HASH ARRAY SCALAR)) {  # scalar last, since a ref is still a scalar
            if (defined *$$data{$t}) {
               $data = *$$data{$t};
               $refsteps .= 'GLOB';
               last;
            }
         }
      }
   }
   
   $ref = reftype \$data unless ($ref);
   $ref = 'UNDEF'        unless (defined $data);

   return (
      $class,
      ($ref eq 'SCALAR') ? (looks_like_number $data ? 'NUMBER' : 'STRING').$refsteps : undef,
      $ref.$refsteps,
   );
}

=head2 try_refkind

=over

=item Exporter Tag: :util

=item Arguments: $data

=item Return Value: @defined_list_of_refkinds

=back

This method is similiar to C<refkind>, but it does two things to the C<refkind> list:
1. removes any blanks, and 2. adds the superclasses C<NONREF> and C<DEFAULT>.  Thus,
you end up with a list with some of the following (in order):

   (
      $class,        # The class name, if blessed
      $scalar_type,  # NUMBER, STRING, NUMBERREF, etc.
      $ext_reftype,  # SCALAR, UNDEF, ARRAYREF, IOREF, VSTRINGREF, RegexpREF, etc.
      $nonref,       # NONREF if either a SCALAR or UNDEF, else ()
      'DEFAULT'      # always there, always last
   )

Don't depend on the array locations, as blanks are removed.  Also, this may return
other superclasses in the future, so don't depend on the size, either.

Like C<refkind>, you really don't need to use this sub, but you should understand
what it returns to be able to use the rest of the subs below.

=cut
 
sub try_refkind {
   my ($data) = @_;
   my @try = (refkind($data));
   my $ref = $try[2];
  
   # Other superclasses
   push @try, 'NONREF' if ($ref eq 'SCALAR' || $ref eq 'UNDEF');
   push @try, 'DEFAULT';
  
   return (grep { !!$_ } @try);
}

sub switch_refkind {
   my ($data, $dispatch_table) = @_;
   die "Dispatch table must be a HASHREF!" unless (reftype $dispatch_table eq 'HASH');
   
   my $coderef;
   my @try = try_refkind($data);
   foreach my $refkind (@try) {
      if ($coderef = $dispatch_table->{$refkind}) {
         die "Dispatch entry for $refkind must be a CODEREF!" unless (reftype $coderef eq 'CODE');
         last;
      }
   }

   die 'No dispatch entry for data=[ '.join(', ', @try).' ]'
      unless $coderef;

   $coderef->();
}

sub method_for_refkind {
   my ($obj, $prefix, $data) = @_;
 
   my @try = try_refkind($data);
   my $method = first { $obj->can($prefix."_$_") } map { s/\W/_/g; } @try;
 
   return $method ? $prefix."_$method" : undef;
}

sub sub_for_refkind {
   return method_for_refkind((caller)[0], @_);
}

sub call_method_for_refkind {
   my ($obj, $prefix, $data) = splice(@_, 0, 3);
   my $method = method_for_refkind($obj, $prefix, $data) || do {
      my @try = try_refkind($data);
      die "Cannot dispatch on ".blessed($obj)."->$prefix".'_[METHOD] for data=['.join(', ', @try).' ]';
   };
   
   $obj->$method(@_);
}

sub call_sub_for_refkind {
   return call_method_for_refkind((caller)[0], @_);
}

1;
