package Bio::Pfam::ColourAlign;

use strict;
use warnings;
our ($groups, $class, $colours);


#&printCSS;
#my $alignRef = &parseAlign;
#my $conRef = &parseConsensus;
#&markupAlign($alignRef, $conRef);





sub printCSS {
    open(CSS, ">alignment.css") || die "Could not open ccs:[$!]\n";
    foreach my $className (sort{$a <=>$b} keys %$colours){
	print CSS "span.S".$className."{background-color:".$colours->{$className}.";color:#FFFFFF}\n";
	print CSS "span.T".$className."{color:".$colours->{$className}."}\n";
    }
    close(CSS);
}


sub parseAlign {
    my $FH = shift;
    my %align;
    #open(ALIGN, "Daxx/ALIGN") || die "Could not open align\n";
    while(<$FH>){
	if(/(\S+\/\d+\-\d+)\s+(.*)/){
	    $align{$1}=$2;
	}else{
	    warn "$_ is an unrecognised alignment line\n";
	}
    }
    #close(ALIGN);
    return \%align;
}

sub parseConsensus{
    my $consensus = shift;
    my @c = split(//,$consensus);
    return(\@c);
}


sub markupAlign{
    my $alignRef = shift;
    my $conRef = shift;
    my $currentClass = 0;

    my ($css, $r, $R);
    print "<pre>\n<div class=align>";
    foreach my $nse (keys %$alignRef){
	my $i = 0;
	print "<div class=alirow><span class=nse>$nse   </span>";
	while($alignRef->{$nse}){
	    $r = substr($alignRef->{$nse}, 0, 1, "");
	    $R = uc $r;
	    
	    
	    if($R eq "." || $R eq "-"){
		print "<span class=black>$r</span>";
		$i++;
		next;
	    }elsif($R eq $conRef->[$i]){
		$css = "S".$class->{$R};
		print "<span class=$css>$r</span>";
		$i++;
		next;
	    }elsif($groups->{$conRef->[$i]}->{$R}){
		$css = "T".$class->{$R};
		print "<span class=$css>$r</span>";
		$i++;
		next;
	    }else{
		print "<span class=black>$r</span>";
		$i++;
		next;
	    }
	    
	    
	}
	print "</div>\n";
    }
    print "</div>\n";
    print "</pre>";
}



#These are build at compile time as it makes it faster running in modperl and
#as they should not be altered.  I have put them down here to make the code a 
#little cleaner.

BEGIN{
$groups =  {'a' => { F => 1, Y => 1, W => 1, H => 1 },
	       'l' => { I => 1, V => 1, L => 1},
	       'h' => { I => 1, V => 1, L => 1, F => 1, Y => 1, W => 1, H => 1,  A => 1, G => 1, M => 1 , C => 1, K => 1, R => 1, T => 1},
	       '+' => { H => 1, K => 1, R => 1 },
	       '-' => { D => 1, E => 1},
	       'c' => { H => 1, K => 1, R => 1, D => 1, E => 1},
	       'p' => { H => 1, K => 1, R => 1, D => 1, E => 1, Q => 1, N => 1, S=> 1, T => 1, C => 1},
	       'o' => { S => 1, T => 1},
	       'u' => { G => 1, A => 1, S => 1},
	       's' => { G => 1, A => 1, S => 1, V => 1, T => 1, D => 1, N => 1, P => 1, C => 1 },
	       't' => { G => 1, A => 1, S => 1, H => 1, K => 1, R => 1, D => 1, E => 1, Q => 1, N => 1, T => 1, C => 1}
	   };


$class = {
    'a' => 1,
    'l' => 2,
    'h' => 3,
    '+' => 4,
    '-' => 5,
    'c' => 6,
    'p' => 7,
    'o' => 8,
    'u' => 9,
    's' => 10,
    't' => 11,
    'A' => 12,
    'B' => 13,
    'C' => 14,
    'D' => 15,
    'E' => 16,
    'F' => 17,
    'G' => 18,
    'H' => 19,
    'I' => 20,
    'K' => 21,
    'L' => 22,
    'M' => 23,
    'N' => 24,
    'P' => 25,
    'Q' => 26,
    'R' => 27,
    'S' => 28,
    'T' => 29,
    'V' => 30,
    'W' => 31,
    'X' => 32,
    'Y' => 33,
    'Z' => 34     
    };

$colours = {
    '1'  => "#009900", 	     #aromatic
    '2'  => "#33cc00", 	     #aliphatic
    '3'  => "#33cc00", 	     #hydrophobic
    '4'  => "#cc0000",	     #positive charge
    '5'  => "#0033ff",	     #negative charge
    '6'  => "#6600cc", 	     #charged
    '7'  => "#0099ff", 	     #polar
    '8'  => "#0099ff", 	     #alcohol
    '9'  => "#33cc00", 	     #tiny
    '10' => "#33cc00", 	     #small
    '11' => "#33cc00", 	     #turnlike
    '12' => "#197fe5",    #hydrophobic
    '13' => "#ff11ff",    #D or N
    '14' => "#ffff11",    #cysteine
    '15' => "#ff11ff",    #clustal-pink, negative charge
    '16' => "#ff11ff",   #clustal-pink         #negative charge
    '17' => "#197fe5",  #clustal-dull-blue    #large hydrophobic
    '18' => "#ff7f11", # clustal-orange       #glycine
    '19' => "#197fe5", #clustal-dull-blue    #large hydrophobic
    '20' => "#197fe5", #clustal-dull-blue    #hydrophobic
    '21' => "#ff1111", #clustal-red          #positive charge
    '22' => "#197fe5", #clustal-dull-blue    #hydrophobic
    '23' => "#197fe5", #clustal-dull-blue    #hydrophobic
    '24' => "#11dd11", #clustal-green        #polar
    '25' => "#ffff11", #clustal-yellow       #proline
    '26' => "#11dd11", #clustal-green        #polar
    '27' => "#ff1111", #clustal-red          #positive charge
    '28' => "#11dd11", #clustal-green        #small alcohol
    '29' => "#11dd11", #clustal-green        #small alcohol
    '30' => "#197fe5", #clustal-dull-blue    #hydrophobic
    '31' => "#197fe5", #clustal-dull-blue    #large hydrophobic
    '32' => "#666666", #clustal-dark-gray    #any
    '33' => "#11ffff", #clustal-cyan         #large hydrophobic
    '34' => "#ff11ff" #clustal-pink         #E or Q
    };
}
1;
