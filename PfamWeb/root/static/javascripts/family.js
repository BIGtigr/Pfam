
// family.js
// jt6 20060721 WTSI
//
// javascript glue for the family section
//
// $Id: family.js,v 1.17 2007-06-26 11:56:53 jt6 Exp $

// Copyright (c) 2007: Genome Research Ltd.
// 
// Authors: Rob Finn (rdf@sanger.ac.uk), John Tate (jt6@sanger.ac.uk)
// 
// This is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//  
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//  
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
// or see the on-line version at http://www.gnu.org/copyleft/gpl.txt

// this will make the ajax calls for the family page components

function familyPostLoad() {
  // structure image
  if( typeof( loadOptions.si.uri ) != "undefined" ) {
  new Ajax.Request( loadOptions.si.uri,
            { method:     'get', 
              parameters: loadOptions.si.params,
              onSuccess:  siSuccess
              // not even bothering with a failure callback...
            } );
  }
  
  // domain graphics
  if( typeof( loadOptions.dg.uri ) != "undefined" ) {
  new Ajax.Request( loadOptions.dg.uri,
            { method:     'get', 
              parameters: loadOptions.dg.params,
              onSuccess:  dgSuccess,
              onFailure:  dgFailure
            } );
  }

  // species tree
  if( typeof( loadOptions.st.uri ) != "undefined" ) {
  new Ajax.Request( loadOptions.st.uri,
            { method:     'get', 
              parameters: loadOptions.st.params,
              onSuccess:  stSuccess,
              onFailure:  stFailure
            } );
  }

  // alignment tree
  if( typeof( loadOptions.at.uri ) != "undefined" ) {
  new Ajax.Request( loadOptions.at.uri,
            { method:     'get', 
              parameters: loadOptions.at.params,
              onSuccess:  atSuccess,
              onFailure:  atFailure
            } );
  }
  // clan structure tab
  if( typeof( loadOptions.fstruc.uri ) != "undefined" ) {
   new Ajax.Request( loadOptions.fstruc.uri,
             { method:     'get', 
               parameters: loadOptions.fstruc.params,
               onSuccess:  fstrucSuccess,
               onFailure:  fstrucFailure
             } );
  }
  // coloured alignment
  if( typeof( loadOptions.ca.uri ) != "undefined" ) {
  new Ajax.Request( loadOptions.ca.uri,
            { method:     'get', 
              parameters: loadOptions.ca.params,
              onSuccess:  caSuccess,
              onFailure:  caFailure
            } );
  }
}

//------------------------------------------------------------
// callback for the structure image call

function siSuccess( oResponse ) {
  Element.update( $("siph"), oResponse.responseText );
}

//------------------------------------------------------------
// callbacks for the domain graphics generation call

function dgSuccess( oResponse ) {
  Element.update( $("dgph"), oResponse.responseText );
}
function dgFailure() {
  Element.update( $("dgph"), "Domain graphics loading failed." );
}

//------------------------------------------------------------
// callbacks for the species tree generation call

var tree;
function stSuccess( oResponse ) {
  tree = new YAHOO.widget.TreeView("treeDiv");
  var root = tree.getRoot();
  eval( oResponse.responseText );
  tree.draw();
}
function stFailure() {
  Element.update( $("stph"), "Tree loading failed." );
}

//------------------------------------------------------------
//- alignment tree methods -----------------------------------
//------------------------------------------------------------

// callbacks for the alignment tree generation call

function atSuccess( oResponse ) {
  Element.update( $("alignmentTree"), oResponse.responseText );
}

function atFailure() {
  var p = $("atph");

  // if a previous update succeeds, the "atph" should have
  // disappeared. We need to re-create it before trying to update it
  // with an error message...
  if( ! p ) {
  p = document.createElement( "p" );
  p.id = "atph";
  var parent = $("alignmentTree");
  parent.insertBefore( p, parent.firstChild );
  }
  Element.update( $("atph"), "Alignment tree loading failed." );
}

//------------------------------------------------------------
//- DAS sequence alignment viewer methods --------------------
//------------------------------------------------------------

// callbacks for the coloured alignment

function caSuccess( oResponse ) {
  $("caph").update( oResponse.responseText );
}

function caFailure() {
  $("caph").update( "Coloured alignment loading failed." );
}

//------------------------------------------------------------
// function to submit the alignment generation form  

function generateAlignment( page ) {
//  console.debug( "generateAlignment: showing page |" + page + "|" );

  // disable various bits of the page and show the spinner
  $( "pagingForm" ).disable();
  $( "handle" ).removeClassName( "sliderHandle" );
  $( "handle" ).addClassName( "disabledSliderHandle" );
  slider.setDisabled();
 
  $( 'spinner' ).show();

  // submit the form
  new Ajax.Updater( "caph",
                    loadOptions.ca.uri, 
                    {   parameters:  'page='         + page +
                                     '&acc='         + $F('acc') +
                                     '&numRows='     + $F('numRows') +
                                     '&scrollValue=' + $F('scrollValue'),
                        evalScripts: true
                    }
                  );

}

//------------------------------------------------------------
// scroll the element horizontally based on its width and the slider 
// maximum value

function scrollHorizontal( value, element, slider ) {
  
  // set the scroll position of the alignment
	element.scrollLeft =
    Math.round( value / slider.maximum * ( element.scrollWidth - element.offsetWidth ) );

  // store the value of the slider in the form
  $('scrollValue').value = value;

}

//------------------------------------------------------------
// tweak the alignment to add links to the sequence IDs

var slider;
function formatAlignment( sURLBase, oSlider ) {
  slider = oSlider;

  // pre-compile a regular expression to filter out the ID, start and
  // end residues
  var re = /^(.*?)\/(\d+)\-(\d+)$/;

  // get all of the spans in the key and walk the list to add link tags
  var spans = $("alignmentKey").getElementsByTagName( "span" );
  $A( spans ).each( function( row ) {
      var s  = row.firstChild.nodeValue;
      var ar = re.exec( s );
  
      // build the link
      var a = document.createElement( "a" );
      var t = document.createTextNode( ar[1] );
      a.appendChild( t );
      a.setAttribute( "href", sURLBase + ar[1] );
      a.setAttribute( "onclick", 
                      "window.open(this.href,'pfamProteinWindow');return false;" );
  
      row.replaceChild( a, row.firstChild );
  
      // tack on the residue range, as plain text for now at least
      var r = document.createTextNode( "/" + ar[2] + "-" + ar[3] );
      row.appendChild( r );
    }
  );
}

//------------------------------------------------------------
//- species tree methods -------------------------------------
//------------------------------------------------------------

//------------------------------------------------------------
// toggle the highlighting of those sequences which are found in the 
// seed alignment

var seedsHighlighted = true;

function toggleHighlightSeed() {
  if( seedsHighlighted ) {
  var links = $A( document.getElementsByClassName("highlightSeed", "treeDiv") );
  links.each( function( a ) {
          Element.removeClassName( a, "highlightSeed" );
        } );
  Element.update( "seedToggle", "Show" );
  } else {
  var divs = $A( document.getElementsByClassName("seedNode", "treeDiv") );
  divs.each( function( d ) {
         if( nodeMapping[d.id] ) {
           Element.addClassName( $(nodeMapping[d.id].labelElId), "highlightSeed" );
         }
         } );
  Element.update( "seedToggle", "Hide" );
  }
  seedsHighlighted = !seedsHighlighted;
}

// the $$() function in prototype is variously described as wonderful
// or immensely slow, so we'll ditch it in favour of walking the DOM
// ourselves. This function is just here for historical reasons...
// jt6 20061016 WTSI
//
// function toggleHighlightSeedSlowly() {
//   if( seedsHighlighted ) {
//   $$(".highlightSeed").each( function( summary ) {
//     Element.removeClassName( summary, "highlightSeed" );
//     } );
//   } else {
//   $$(".seedNode").each( function( summary ) {
//     if( nodeMapping[summary.id] ) {
//       Element.addClassName( $(nodeMapping[summary.id].labelElId), "highlightSeed" );
//     }
//     } );
//   }
//   seedsHighlighted = !seedsHighlighted;
// }

//------------------------------------------------------------
// toggle showing/hiding of the node summaries

var summariesVisible = true;

function toggleShowSummaries() {
  if( summariesVisible ) {
  $$("div.nodeSummary").each( function( node ) {
        Element.hide( node );
      } );
  Element.update( "sumToggle", "Show" );
  } else {
  $$("div.nodeSummary").each( function( node ) {
        Element.show( node );
      } );
  Element.update( "sumToggle", "Hide" );
  }
  summariesVisible = !summariesVisible;
}

// turns out that the $$() function is quicker than walking the tree
// in this case... who knew ?
// jt6 20061016 WTSI
//
// function toggleShowSummariesSlowly() {
//   var divs = $A( document.getElementsByClassName("nodeSummary","treeDiv") );
//   if( summariesVisible ) {
//   divs.each( function( d ) {
//         Element.hide( d );
//         } );
//   } else {
//   divs.each( function( d ) {
//         Element.show( d );
//         } );
//   }
//   summariesVisible = !summariesVisible;
// }

//------------------------------------------------------------
// collect the sequences that are specified by the checked leaf nodes
// in the tree. Submit the form in the page which will act on those
// accessions

function collectSequences( acc ) {

  var seqs = "";

  var leaves = $A( document.getElementsByClassName( "leafNode", "treeDiv" ) );
  leaves.each( function( n ) {
         var taskNode = nodeMapping[n.id];
         if( taskNode.checked ) {
           seqs = seqs + nodeSequences[n.id] + " ";
         }
         } );
  
  // build the URI, escaping the sequences string, just to be on the safe side
  var url = selectURI + "?acc=" + acc + "&amp;seqs=" + escape( seqs );

  // and submit the request
  popUp( url, 'console', 800, 800, 'selectedSeqsWin' );
}

//------------------------------------------------------------
// expand the tree to the depth specified in the little form in the
// tools palette

function expandToDepth() {
  tree.collapseAll();
  expandTo( $F("depthSelector"), tree.root );
}

// the method that actually expands to a given depth. Should really
// only be called by expandToDepth()
var currentDepth = 0;

function expandTo( finalDepth, node ) {

  if( currentDepth < finalDepth - 1 ) {

    for( var i=0; i< node.children.length; ++i ) {
    
      var c = node.children[i];
      c.expand();

    currentDepth++;
      expandTo( finalDepth, c );
    currentDepth--;
    }
  }

}

//------------------------------------------------------------
// show/hide the tree tools palette

function toggleTools() {
  if( Element.visible("treeToolsContent") ) {
  Element.hide( "treeToolsContent" );
  Element.update( "toolsToggle", "Show" );
  } else {
  Element.show( "treeToolsContent" );
  Element.update( "toolsToggle", "Hide" );
  }
}

//------------------------------------------------------------
var numColsTable;

function fstrucSuccess( oResponse ) {
  Element.update( "familyStructureTabHolder", oResponse.responseText );
        // how many columns are there in the table ?
      var firstRow = $("structuresTable").getElementsByTagName("tr")[1]
      numColsTable  = firstRow.getElementsByTagName("td").length;

      // walk over all of the cells in the table and add listeners for mouseover and 
      // mouseout events
      $A( $("structuresTable").getElementsByTagName( "td" ) ).each( function( cell ) {
          cell.onmouseover = highlight.mouseoverHandler.bindAsEventListener( highlight );
          cell.onmouseout  = highlight.mouseoutHandler.bindAsEventListener( highlight );
        }
   );


}

function fstrucFailure() {
  Element.update( "fstrucph", "Graphics loading failed." );
}
