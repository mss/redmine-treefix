use strict;
use warnings;
use 5.010;
use Dumper;

use DBI;

my $database = "redmine";
my $username = "root";
my $password = "password";

my $table    = "projects";


my @rows;
my $tree = {
    id         => undef,
    parent_id  => undef,
    lft        => undef,
    rgt        => undef,
    identifier => "root",
    name       => "Virtual Root",
    children   => [],
};

my $count = 0;

sub main {
    @rows = fetch_data;

    $tree = build_tree;
    $tree = update_tree;

    print Dumper($tree);
    dump_sql;
}

sub fetch_data {
    my $dbh = DBD->connect(
        "DBI:mysql:$database",
        $username,
        $password,
    ) or die "Could not connect to $database: $DBI::errstr";

    my $rows = $dbh->selectall_arrayref(
        'SELECT id,parent_id,lft,rgt,identifier,name FROM ? ORDER BY id ASC',
        undef,
        $table,
    );

    $dbh->disconnect;

    return @{$rows};
}

sub build_tree {
    my $root = shift || $tree;

    my @children = sort {
            $a->{'identifier'} cmp $b->{'identifier'}
        } grep {
            $_->{'parent_id'} ~~ $root->{'id'}
        } @rows;
    map build_tree @children;

    $root->{'children'} = \@children;
    return $root;
}

sub update_tree {
    my $root = shift || $tree;

    $root->{'lft_old'} = $root->{'lft'};
    $root->{'lft'}     = $count++;

    map update_tree @{$root->{'children'}};

    $root->{'rgt_old'} = $root->{'rgt'};
    $root->{'rgt'}     = $count++;
}

sub dump_sql {
    printf("USE %s;\n",
        $database
    );
    printf("START TRANSACTION;\n");

    my $p = 1 + int(log($row[-1]->{'id'}) / log(10));
    my $d = "0${p}d";
    foreach my $row (@rows) {
        printf("/* (%$d, %$d): (%$d, %$d) -> (%$d, %$d) %s: %s */\n",
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

    printf("COMMIT;\n");
}


exit main;
