
// family.js
// jt6 20060721 WTSI
//
// javascript glue for the family section
//
// $Id: family.js,v 1.32 2008-06-02 14:42:55 jt6 Exp $

// Copyright (c) 2007: Genome Research Ltd.
// 
// Authors: Rob Finn (rdf@sanger.ac.uk), John Tate (jt6@sanger.ac.uk)
// 
// This is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation; either version 2 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.

// this will make the ajax calls for the family page components

function familyPostLoad() {
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
// callbacks for the domain graphics generation call

function dgSuccess( oResponse ) {
  $("dgph").update( oResponse.responseText );
}
function dgFailure() {
  $("dgph").update( "Domain graphics loading failed." );
}

//------------------------------------------------------------
//- alignment tree methods -----------------------------------
//------------------------------------------------------------

// callbacks for the alignment tree generation call

function atSuccess( oResponse ) {
  $("alignmentTree").update( oResponse.responseText );
}

function atFailure() {
  var p = $("atph");

  // if a previous update succeeded, the "atph" should have
  // disappeared. We need to re-create it before trying to update it
  // with an error message...
  if( ! p ) {
    p = document.createElement( "p" );
    p.id = "atph";
    var parent = $("alignmentTree");
    parent.insertBefore( p, parent.firstChild );
  }
  $("alignmentTree").update( "Alignment tree loading failed." );

  // disable the form now, otherwise we'll end up chasing our tail...
  $('phyloForm').disable();
}

//------------------------------------------------------------
//- DAS sequence alignment viewer methods --------------------
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
                      "opener.location=this.href;return false;" );
  
      row.replaceChild( a, row.firstChild );
  
      // tack on the residue range, as plain text for now at least
      var r = document.createTextNode( "/" + ar[2] + "-" + ar[3] );
      row.appendChild( r );
    }
  );
}

//------------------------------------------------------------
var numColsTable;

function fstrucSuccess( oResponse ) {
  $("familyStructureTabHolder").update( oResponse.responseText );
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
  $("fstrucph").update( "Graphics loading failed." );
}
