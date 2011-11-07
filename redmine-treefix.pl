use strict;
use warnings;
use 5.010;

use Getopt::Std;
use Data::Dumper;
$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;

use DBI;

my $database = "redmine";
my $username = "root";
my $password = "";

my $table    = "projects";
my $sortby   = "name";

my $dodump;


my @rows;
my $tree = {
    id         => undef,
    parent_id  => undef,
    lft        => undef,
    rgt        => undef,
    identifier => "root",
    name       => "Virtual Root",
    x          => [],
};

my $count = 0;

sub parse_args;
sub fetch_data;
sub build_tree;
sub update_tree;
sub dump_sql;

sub main {
    parse_args;

    @rows = fetch_data;

    $tree = build_tree;
    if ($dodump) {
        print STDERR "original tree: ";
        print STDERR Dumper($tree);
    }
    $tree = update_tree;
    if ($dodump) {
        print STDERR "updated tree:  ";
        print STDERR Dumper($tree);
    }

    dump_sql;
}

sub parse_args {
    my %opts;
    getopts('d:u:p:t:s:D', \%opts) or die;
    $database = $opts{'d'} if $opts{'d'};
    $username = $opts{'u'} if $opts{'u'};
    $password = $opts{'p'} if $opts{'p'};
    $table    = $opts{'t'} if $opts{'t'};
    $sortby   = $opts{'s'} if $opts{'s'};
    $dodump   = $opts{'D'};
}

sub fetch_data {
    my $dbh = DBI->connect(
        "DBI:mysql:$database",
        $username,
        $password,
    ) or die;

    my $rows = $dbh->selectall_hashref(
        'SELECT id,parent_id,lft,rgt,identifier,name FROM ' . $table,
        'id',
        undef,
    ) or die;

    $dbh->disconnect;

    return sort {
            lc($a->{$sortby}) cmp lc($b->{$sortby})
        } values %{$rows};
}

sub build_tree {
    my $root = shift || $tree;

    my @children = grep {
            $_->{'parent_id'} ~~ $root->{'id'}
        } @rows;
    map { build_tree $_ } @children;

    $root->{'x'} = \@children;
    return $root;
}

sub update_tree {
    my $root = shift || $tree;

    $root->{'lft_old'} = $root->{'lft'};
    $root->{'lft'}     = $count++;

    map { update_tree $_ } @{$root->{'x'}};

    $root->{'rgt_old'} = $root->{'rgt'};
    $root->{'rgt'}     = $count++;

    return $root;
}

sub dump_sql {
    printf("USE %s;\n",
        $database
    );
    printf("START TRANSACTION;\n\n");

    my $p = 1 + int(log($rows[-1]->{'id'}) / log(10));
    my $d = "0${p}d";
    foreach my $row (sort { $a->{'lft'} <=> $b->{'lft'} } @rows) {
        printf("/* (%$d, %$d): (%$d, %$d) -> (%$d, %$d) %s: '%s' */\n",
            $row->{'parent_id'} || 0,
            $row->{'id'},
            $row->{'lft_old'},
            $row->{'rgt_old'},
            $row->{'lft'},
            $row->{'rgt'},
            $row->{'identifier'},
            $row->{'name'},
        );
        printf("UPDATE %s SET lft = %d, rgt = %d WHERE id = %d;\n",
            $table,
            $row->{'lft'},
            $row->{'rgt'},
            $row->{'id'},
        );
    }

    printf("\nCOMMIT;\n");
}


exit main;
