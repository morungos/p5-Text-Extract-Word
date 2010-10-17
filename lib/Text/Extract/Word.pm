package Text::Extract::Word;

use strict;
use warnings;

our $VERSION = 0.01;

use parent qw(Exporter);

our @EXPORT_OK = qw(get_all_text);

use Encode;
use POSIX;
use OLE::Storage_Lite;
use IO::File;

sub _compare_ranges {
    my ($range1, $range2) = @_;
    return ($range1->[0] <=> $range2->[0]);
}

sub extract_stream {
    my ($fh) = @_;
    
    my $ofs = OLE::Storage_Lite->new($fh);
    my $name = encode("UCS-2LE", "WordDocument");
    my @pps = $ofs->getPpsSearch([$name], 1, 1);
    die("This does not seem to be a Word document") unless (@pps);
    
    # OK, at this stage, we have the word stream. Now we need to start reading from it.
    my $data = $pps[0]->{Data};
    
    my $magic = unpack("v", substr($data, 0x0000, 2));
    die(sprintf("This does not seem to be a Word document, but it is pretending to be one: %x", $magic)) unless ($magic == 0xa5ec);
    
    my $flags = unpack("v", substr($data, 0x000A, 2));
    my $table = ($flags & 0x0200) ? "1Table" : "0Table";
    $table = encode("UCS-2LE", $table);
    
    @pps = $ofs->getPpsSearch([$table], 1, 1);
    die("Could not locate table stream") unless (@pps);
    
    $table = $pps[0]->{Data};
    
    my $fcMin = unpack("V", substr($data, 0x0018, 4));
    my $ccpText = unpack("V", substr($data, 0x004c, 4));
    my $ccpFtn = unpack("V", substr($data, 0x0050, 4));
    my $ccpHdd = unpack("V", substr($data, 0x0054, 4));
    my $ccpAtn = unpack("V", substr($data, 0x005c, 4));
    
    my $charPLC = unpack("V", substr($data, 0x00fa, 4));
    my $charPlcSize = unpack("V", substr($data, 0x00fe, 4));
    my $parPLC = unpack("V", substr($data, 0x0102, 4));
    my $parPlcSize = unpack("V", substr($data, 0x0106, 4));

    #get the location of the piece table
    my $complexOffset = unpack("V", substr($data, 0x01a2, 4));

#    print STDERR "fcMin: $fcMin\n";
#    print STDERR "ccpText: $ccpText\n";
#    print STDERR "ccpFtn: $ccpFtn\n";
#    print STDERR "ccpHdd: $ccpHdd\n";
#    print STDERR "ccpAtn: $ccpAtn\n";
#    print STDERR "end: ".($ccpText + $ccpFtn + $ccpHdd + $ccpAtn)."\n";

    my @pieces = _find_text(\$table, $complexOffset);
    @pieces = sort { $a->[0] <=> $b->[0] } @pieces;
    
    my $body = _get_text(\$data, \@pieces);
    
    return $body;
}

sub _get_text {
    my ($dataref, $piecesref) = @_;
    
    my @pieces = @$piecesref;
    my @result = ();
    my $index = 1;
    my $position = 0;
    
    foreach my $piece (@pieces) {
        my ($pstart, $ptotLength, $pfilePos, $punicode) = @$piece;
        my $pend = $pstart + $ptotLength;
        my $textStart = $pfilePos;
        my $textEnd = $textStart + ($pend - $pstart);
        
        if ($punicode) {
            push @result, _add_unicode_text($textStart, $textEnd, $dataref);
#            print STDERR "Adding unicode text from $index: $textStart to $textEnd (bytes: $ptotLength; position: $position)\n";
            $position += $ptotLength/2;
        } else {
            push @result, _add_text($textStart, $textEnd, $dataref);
#            print STDERR "Adding text from $index: $textStart to $textEnd (bytes: $ptotLength; position: $position)\n";
            $position += $ptotLength;
        }  
        $index++;
    }

#    print STDERR "Complete; position: $position\n";

    my $theResult = join("", @result);
    return $theResult;
}

sub _add_unicode_text {
    my ($textStart, $textEnd, $dataref) = @_;

    my $string = substr($$dataref, $textStart, 2*($textEnd - $textStart));

    my $perl_string = Encode::decode("UCS-2LE", $string);
    return $perl_string;
}

sub _add_text {
    my ($textStart, $textEnd, $dataref) = @_;
    
    my $string = substr($$dataref, $textStart, $textEnd - $textStart);
    
    my $perl_string = Encode::decode("iso-8859-1", $string);
    return $perl_string;
}

sub _get_chunks {
    my ($start, $length, $piecesref) = @_;
    my @result = ();
    my $end = $start + $length;
    
    foreach my $piece (@$piecesref) {
        my ($pstart, $ptotLength, $pfilePos, $punicode) = @$piece;
        my $pend = $pstart + $ptotLength;
        if ($pstart < $end) {
            if ($start < $pend) {
                push @result, $piece;
            }
        } else {
            last;
        }
    }
    
    return @result;
}

sub _find_text {
    my ($tableref, $pos) = @_;
    
    my @pieces = ();
    
    while(unpack("C", substr($$tableref, $pos, 1)) == 1) {
        $pos++;
        my $skip = unpack("v", substr($$tableref, $pos, 2));
#        print STDERR sprintf("Skipping %d\n", $skip);
        $pos += 2 + $skip;
    }
    
    if (unpack("C", substr($$tableref, $pos, 1)) != 2) {
         die("corrupted Word file");
    } else {
        my $pieceTableSize = unpack("V", substr($$tableref, ++$pos, 4));
#        print STDERR sprintf("pieceTableSize: %d\n", $pieceTableSize);
        
        $pos += 4;
        my $pieces = ($pieceTableSize - 4) / 12;
#        print STDERR sprintf("pieces: %d\n", $pieces);
        my $start = 0;
        for (my $x = 0; $x < $pieces; $x++) {
            my $filePos = unpack("V", substr($$tableref, $pos + (($pieces + 1) * 4) + ($x * 8) + 2, 4));
            my $unicode = 0;
            if (($filePos & 0x40000000) == 0) {
                $unicode = 1;
            } else {
                $unicode = 0;
                $filePos &= ~(0x40000000); #gives me FC in doc stream
                $filePos /= 2;
            }
#            print STDERR sprintf("filePos: %x\n", $filePos);
            my $lStart = unpack("V", substr($$tableref, $pos + ($x * 4), 4));
            my $lEnd = unpack("V", substr($$tableref, $pos + (($x + 1) * 4), 4));
            my $totLength = $lEnd - $lStart;
            
#            print STDERR "lStart: $lStart; lEnd: $lEnd\n";
            
#            print STDERR ("Piece: " . (1 + $x) . ", start=" . $start
#                            . ", len=" . $totLength . ", phys=" . $filePos
#                            . ", uni=" .$unicode . "\n");
                            
            # TextPiece piece = new TextPiece(start, totLength, filePos, unicode);
            # start = start + totLength;
            # text.add(piece);
            
            push @pieces, [$start, $totLength, $filePos, $unicode];
            $start = $start + (($unicode) ? $totLength/2 :$totLength);
        }
    }
    return @pieces;
}

sub get_all_text {
    my ($file) = @_;
    die("Missing file: $file") unless (-e $file);
    my $oIo = new IO::File("<$file");
    binmode($oIo);
    my $result = extract_stream($oIo);
    return $result;
}

1;

=head1 NAME

Text::Extract::Word - Extract text from Word files

=head1 SYNOPSIS

    use Text::Extract::Word qw(get_all_text);
    
    my $text = get_all_text("test1.doc");

=head1 DESCRIPTION

This simple module allows the textual contents to be extracted from a Word file. 
The code was ported from Java code, originally part of the Apache POE project, but
extensive code changes were made interanlly. 

=head1 FUNCTIONS

=head2 get_all_text($filename)

The only function exported by this module, when called on a file name, returns the
text contents of the Word file. The contents are returned as UTF-8 encoded text. 

=head1 BUGS

=over 4 

=item * support for legacy Word - the module does not extract text from Word version 6 or earlier 

=back

=head1 SEE ALSO

L<OLE::Storage> also has a script C<lhalw> (Let's Have a Look at Word) which extracts
text from Word files. This is simply a much smaller module with lighter dependencies,
using L<OLE::Storage_Lite> for its storage management. 

=head1 AUTHOR

Stuart Watt, stuart@morungos.com

=head1 COPYRIGHT

Copyright (c) 2010 Stuart Watt. All rights reserved.

=cut

