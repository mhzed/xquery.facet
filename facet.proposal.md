
# Proposal to add faceted search support in XQuery

## Introduction

Faceted search has proven to be enormously popular in real world web applications.  As opposed to full text search,
faceted search allows user to navigate and access information via a structured facet classification system.  Combined
with full text search, it gives user enormous power and flexibility to discover information.

This document proposes to introduce faceted-search support into XQuery.  It will describe the technical aspects of
how faceted search is implemented currently, and introduces a set of faceted search XQuery/XPath functions
that are hopefully intuitive to use, and implementation friendly.

## Requirement

The requirements for the API are:

* Intuitive to use
* Friendly to existing implementations:  Lucene's faceted index, and query-time aggregation implementations
* Performance friendly:  allows implementation to be as efficient as possible
* Support all popular facet use patterns: multi-select/dill-sideway, hierarchical/pivot facets.


## Facet implementation details

### Terminologies

* Facet:  refers to an attribute to be categorized.  For example,  "color" is a facet of "car" object.

* Facet-value: refers to a value of Facet.  For example, "blue" is a facet-value of facet "color" for "car" object.

* The facet aggregation: counting the occurrence of each facet-value in results.  Note in some implementation such as
  Lucene, relevance may also be aggregated for ordering purpose: the most relevant category may not be the one with
  most counts.

* The facet drills:
    a. drill-down: filter search results using drilled facet value. Once a facet-value is drilled down, the facet is no
       longer available for selection by user, meaning only one facet-value in the same facet can be drilled-down at
       any given time.
    b. drill-sideway:  also known as multi-select facets. Filter search results using drilled facet value. The facet
       is still available for selection in UI.  Two or more facet-values in the same facet can be drilled
       at any given time.

    Drill down example:

        - Color                                  >> Color:blue
          - blue(10)    => User select blue  =>
          - red(6)
          - yellow(2)

    * In UI, Color:blue is now shown as selected (usually displayed as bread-crumb), and the facet "Color" is either
      removed or grey-ed out, no longer available for selection.

    Drill sideway example:

        - Color                          - Color                       - Color
          - blue(10)   => select blue =>   x blue(10)   => select red    x blue(10)
          - red(6)                         - red(6)                      x red(6)
          - yellow(2)                      - yellow(2)                   - yellow(2)


*  Hierarchical facets.  Organizing facets in a hierarchical structure (tree).  For example:
   country->state->city are hierarchical facets.  When a facet is part of hierarchy, it must be aggregated in relation
   to its parent facet.  For example:

       Flat facets                Hierarchical facets, "Color" is child of "Make"

       - Make                     - Make
         - Audi(10)                 - Audi(10)
                         ====>        - Color
       - Color                          - Blue(5)
         - Blue(10)

   There are 10 blue cars in total, but only 5 blue Audi.

### Performance considerations:

Compared to full text search, faceted search's performance requirement is more stringent.  Consider:

1. For one query, many different facets are usually aggregated.
2. Facet aggregation needs to be performed over entire result set, regardless how many results are returned.

Below we will cover some of the implementation techniques, and their performance profile.

### Implementation method 1:  real time aggregation

The most straight forward implementation is to count the facets after the result set is returned by search query.

As XQuery is a turing complete functional programming language, such aggregation can be implemented entirely in XQuery.
Appendix A. demonstrate such implementation.

An implementation can choose to implement facet aggregation in the native code for further performance gain.  The
aggregation can be achieved efficiently in O(n), where n is the size of result set.

In the context of XML database, to avoid excessive random disk IO, it's important to have the faceted fields stored
in the index (Covering Index).  For example if an implementation uses Lucene as its index engine, faceted fields
should also be in Lucene's stored fields.

Real time facet aggregation is sufficient for most applications if implemented efficiently.  However, when the
repository grows large enough, indexing time optimization are required to achieve further performance gain.

### Implementation method 2: facet indexes (Lucene)

For details on Lucene facet index, please refer to official [documentation](http://lucene.apache.org/core/4_4_0/facet/org/apache/lucene/facet/doc-files/userguide.html)

Lucene's implementation of facet can be summed up as following:

1. Facets are defined at indexing time for a document.
2. Facets are written to a taxonomy index, which is hierarchically structured.  And each facet value is mapped to
   a unique integer ordinal in the taxonomy index.
3. Each facet ordinal is invert indexed, for facet drills.
4. For each document, all of its facets are stored in Lucene's DocValues field, for real time aggregation.

Lucene's facet aggregation is faster for the following reasons:

1. DocValues is a more efficient storage form compared with stored fields.  Please see [this](http://www.slideshare.net/lucenerevolution/willnauer-simon-doc-values-column-stride-fields-in-lucene)
2. Facet values are aggregated on its integer ordinal, instead of string content.  This results in less CPU and memory
   usage.
3. For large result set ( > 50% of total documents), the complement set of results can be aggregated instead, by
   subtracting the collected results from total results, we get the actual results.
4. At the sacrifice of precision, sampling technique can be employed to further speed up aggregation.  Detailed
   [here](http://lucene.apache.org/core/4_4_0/facet/org/apache/lucene/facet/doc-files/userguide.html#optimizations).

In terms of algorithmic complexity, Lucene's facet aggregation is the same as real time aggregation.  However, the
availability of facet index allows Lucene to perform above mentioned optimization that are impossible to do otherwise.

### Implementation method 3: BitVector

The bit vector technique is described in detail in this
[paper](http://ilps-vm09.science.uva.nl/PoliticalMashup/uploads/2011/02/fast-faceted-search.pdf)
 and [slides](http://www.anneschuth.nl/wp-content/uploads/2012/08/presentation-export.pdf).

This technique exploits the efficient CPU handling of bit vectors, where logic AND/OR are translated into bitwise
AND/OR, and the count of bits can be achieved in O(log(n)).

For each facet-value, a BitVector is constructed at indexing time where a set bit corresponds to a document that
contains this facet.  When a full text query is executed,  its result set is converted into BitVector, and applied
(bitwise AND) over the BitVector for each facet, the count of set bits in the resulting BitVector is the facet-count.
Facet drills would be similar, simply apply the drilled facet's BitVector on all other facets.

This technique is highly efficient for facet values and search queries that return large result set.  However
maintaining bit vectors proportional to the size of total documents for each facet value in memory is expensive.
And for "sparse" search (i.e. count 10k results in a 10 million doc repository), the speed advantage is reduced.
Regardless, the [paper](http://ilps-vm09.science.uva.nl/PoliticalMashup/uploads/2011/02/fast-faceted-search.pdf)
contains benchmark that suggests that this is the most scalable algorithm for facet aggregation, and it also listed
a few issues.  A more complete analysis is required but beyond the scope of this document.


## The XQuery API

Though the modifications are extensive, the following proposed XQuery APIs references this [paper](http://ilps-vm09.science.uva.nl/PoliticalMashup/uploads/2011/02/fast-faceted-search.pdf).

The facet is returned as "facet" element with RelaxNG grammar:

    Facet = element facet {
      attribute name { text },
      element value {
          attribute name { text },
          xsd:integer,
          Facet*
      }*
    }

Example:

    <facet name="country">
        <value name="US">2</value>
    </facet>


The facet is defined by "facet-def" element with following RelaxNG compact grammar:

    start = FacetDef
    FacetDef = element facet-def {
        element name { text },
        element group-by {
            attribute type { text }?,
            attribute pred { text }?,
            attribute drill { text }?,
            text
        },
        element limit { xsd:integer }?,
        element order-by { attribute direction { "ascending"|"descending" }, "name"|"count"|"relevance" }?,
        FacetDef*
    }

Example:

    <facet-def>
        <name>Country</name>
        <group-by>/location/country</group-by>
        <limit>100</limit>
        <order-by direction="ascending">value</order-by>
    </facet-def>

- element name : name of facet, determines the value /facet/@name returned by facet:count()
- element limit : how many facet values to return.  Optional.  Default returns all facet-values.
- element order-by : how to order returned facet-values.
    * "name" : order by facet value, alphabetically
    * "count" : order by count of facet value
    * "relevance" : order by relevance of facet value.  If implementation does not have a scoring mechanism for results,
       treat this the same as "count".
  if order-by is not specified, then implementation can choose to return facet values in any order.

- element group-by: content contain the xpath, relative to the result object, of the node that contains the facet
  values for aggregation.

  Optionally "group-by" allows predicates to transform the facet values:

  * pred:  text containing the name of XQuery function that transforms facet values, of following signature:

          (: returns () to not count $e,  returns > 1 string to count $e under multiple facet values :)
          declare function local:predicate($e as node()) as xs:string*;

  * drill: text containing the name of XQuery function that is able to drill on transformed facet values.  Signature is:

          (: $drilled-value is what would have been returned above by "pred" function
             returns true to include $e in result, false otherwise :)
          declare function local:drill($e as node(), $drilled-value as xs:string) as xs:boolean;

  Though not enforced, "pred" and "drill" should appear in pair to allow proper facet navigation.

  * type:  this optional attribute is to indicate custom facet implementations.  For example, if implementation
  supports Lucene facet index, then it can choose to allow following facet definition:

        <facet-def>
            <name>Authors</name>
            <group-by type="lucene">/author</group-by>
        </facet-def>

  	Where "/author" is a category path defined in Lucene's taxonomy index.  The returned facets will then look like:

        <facet name="Authors">
          <value name="mark twain">3</value>
          <value name="jack london">2</value>
          <value name="Max Ernst">2</value>
        </facet>

Both "facet-def" and "facet" definitions are recursive, this allows hierarchical facets to be implemented.  See
Appendix A. for specific examples.


----------------------------------------------------------------------------------------

The facet functions.

### facet:count

#### Signature

    declare function facet:count(
      $results as node()* ,
      $facet-defs as element(facet-def)*
    ) as element(facet)*;

#### Properties

This function is: non-deterministic, context-independent, focus-independent

#### Rules

Given a sequence of nodes, and a sequence of facet definitions, count the facet-values for each facet definition.

It's encouraged that an application gathers all facet definitions first and then call this function once, this allows
underlying implementation to aggregate the facets faster by iterating through the result set once.


### facet:filter

#### Signature

    declare function facet:filter(
      $results as node()*,
      $facet-def as element(facet-def),
      $value as xs:string
    ) as node()*;

#### Properties

This function is: deterministic, context-independent, focus-independent

#### Rules

Given a sequence of nodes, a facet definition, and a chosen facet value, return filtered results based on
facet-value.  This function is used for facet-drills.

------------------------------------------------------------

## Appendix A.  XQuery implementation and use cases


Below is an example XQuery that

1. implements above API in pure XQuery.
2. contains various use cases for count and drill

The XQuery is tested with exist-db 2.0.1, and relies on exist-db specific "util:eval()" api.

    declare namespace facet = "http://facet.xquery.com/";

    (: an implementation dependent 'evalGroupby' method is used to evaluate facet values,
       the implementation below uses exist-db's util:eval function :)
    declare function local:evalGroupby ($node as node(), $group-by as element(group-by)) as xs:string* {
      let $xpathExpr := fn:concat("$node", data($group-by) )
      let $expr :=
        if ($group-by/@pred) then fn:concat($group-by/@pred, "(", $xpathExpr, ")")
        else $xpathExpr
      return util:eval( $expr )
    };

    declare function local:evalGroupbyForDrill (
        $node as node(),
        $group-by as element(group-by),
        $drill-value as xs:string
    ) as xs:boolean {
      let $xpathExpr := fn:concat("$node", data($group-by) )
      let $expr :=
        if ($group-by/@drill) then fn:concat($group-by/@drill, "(", $xpathExpr, ", $drill-value)")
        else fn:concat($xpathExpr," eq $drill-value")
      return util:eval( $expr )
    };

    (: the filter function for drill down :)
    declare function facet:filter(
        $results as node()*,
        $facet-def as element(facet-def),
        $value as xs:string
    ) as node()* {
      for $r in $results
      where local:evalGroupbyForDrill($r, $facet-def/group-by, $value)
      return $r
    };

    (: the facet count :)
    declare function facet:count(
      $results as node()* ,
      $facet-defs as element(facet-def)*
    ) as element(facet)* {

      for $facet-def in $facet-defs
      return facet:count-via-xquery($results, $facet-def)
    };

    (: we implement a single facet count using XQuery's group by :)
    declare function facet:count-via-xquery(
        $results as node()*,
        $facet-def as element(facet-def)
    ) as element(value)* {

      (: expand $results, in case of group-by is based on repeating values in an object:)
      let $expandSeq :=
        for $r in $results
        for $v in local:evalGroupby($r, $facet-def/group-by)
        return <r><val>{$v}</val><recs>{$r}</recs></r>

      return
        <facet name="{$facet-def/name}">{
          (: perform count via group by :)
          let $facet-counts :=
            for $e in $expandSeq
            let $val := data($e/val)
            group by $val
            return <value name="{$val}"><c>{count($e)}</c>{$e/recs}</value>

          (: handler order :)
          let $facet-counts :=
              if ($facet-def/order-by eq "name") then
                if ($facet-def/order-by/@direction eq "descending") then
                  for $f in $facet-counts
                  order by $f/@name descending
                  return $f
                else
                  for $f in $facet-counts
                  order by $f/@name
                  return $f
              else if ($facet-def/order-by eq "count" or $facet-def/order-by eq "relevance") then
                (: treat count|relevance as same :)
                if ($facet-def/order-by/@direction eq "descending") then
                  for $f in $facet-counts
                  order by xs:integer($f/c) descending
                  return $f
                else
                  for $f in $facet-counts
                  order by xs:integer($f/c)
                  return $f
              else
                $facet-counts

          (: handle limit :)
          let $facet-counts :=
            if ($facet-def/limit) then subsequence($facet-counts, 1, $facet-def/limit)
            else $facet-counts

          (: handle hierarchical/pivot facet:)
          let $facet-counts :=
            for $f in $facet-counts
            return
              <value name="{$f/@name}">
              {data($f/c)}
              {
                facet:count($f/recs/*, $facet-def/facet-def)
              }
              </value>

          return $facet-counts
        }</facet>
    };

    (: ------------------  implementation ends, example begins --------------------- :)

    (: Customized group-by predicates, come in pairs :)
    declare function local:group-by-year($e as node()) as xs:string* {
      fn:substring(string($e), 1, 4)
    };
    declare function local:drill-by-year($e as node(), $value as xs:string) as xs:boolean {
      if (fn:substring(string($e), 1, 4) eq $value) then true()
      else false()
    };

    declare function local:group-by-age-range($e as node()) as xs:string* {
      let $n := xs:integer(data($e))
      return
        if ($n < 20) then "<20"
        else if ($n < 30) then "20+"
        else if ($n < 40) then "30+"
        else ()   (: do not count :)
    };
    declare function local:drill-by-age-range($e as node(), $value as xs:string) as xs:boolean {
      let $n := xs:integer(data($e))
      return
        if ($value eq "<20") then $n < 20
        else if ($value eq "20+") then $n >= 20 and $n < 30
        else if ($value eq "30+") then $n >= 30 and $n < 40
        else false()
    };

    declare function local:group-by-region($gps as element(gps)) as xs:string* {
      if ($gps/latitude > 40) then "Northern US"
      else "Southern US"
    };
    declare function local:drill-by-region($gps as element(gps), $value as xs:string) as xs:boolean {
      if ($value eq "Northern US") then $gps/latitude > 40
      else $gps/latitude <= 40
    };


    let $data :=
    <sample>
      <employee>
        <name>John Doe</name>
        <sex>Male</sex>
        <organization>HR</organization>
        <location>
          <country>US</country>
          <state>CA</state>
          <city>Pleasanton</city>
          <gps>
            <longitude>-95.677068</longitude>
            <latitude>37.0625</latitude>
          </gps>
        </location>
        <age>21</age>
        <employDate>2010-02-01</employDate>
        <skills>
          <skill>word</skill>
          <skill>excel</skill>
          <skill>windows</skill>
        </skills>
      </employee>

      <employee>
        <name>Jane Joe</name>
        <sex>Female</sex>
        <organization>Finance</organization>
        <location>
          <country>US</country>
          <state>CA</state>
          <city>San Francisco</city>
          <gps>
            <longitude>-122.419416</longitude>
            <latitude>37.77493</latitude>
          </gps>
        </location>
        <age>18</age>
        <employDate>2003-02-01</employDate>
        <skills>
          <skill>word</skill>
          <skill>excel</skill>
          <skill>powerpoint</skill>
          <skill>linux</skill>
        </skills>
      </employee>

      <employee>
        <name>Steve</name>
        <sex>Male</sex>
        <organization>HR</organization>
        <location>
          <country>US</country>
          <state>WA</state>
          <city>Seattle</city>
          <gps>
            <longitude>-122.332071</longitude>
            <latitude>47.60621</latitude>
          </gps>
        </location>
        <age>31</age>
        <employDate>2010-04-01</employDate>
        <skills>
          <skill>openoffice</skill>
          <skill>word</skill>
        </skills>
      </employee>

      <employee>
        <name>Kylie</name>
        <sex>Female</sex>
        <organization>Sales</organization>
        <location>
          <country>US</country>
          <state>WA</state>
          <city>Bellingham</city>
          <gps>
            <longitude>-122.488225</longitude>
            <latitude>48.759553</latitude>
          </gps>
        </location>
        <age>23</age>
        <employDate>2010-06-01</employDate>
        <skills>
          <skill>word</skill>
          <skill>powerpoint</skill>
        </skills>
      </employee>

      <employee>
        <name>Kyle</name>
        <sex>Male</sex>
        <organization>Sales</organization>
        <location>
          <country>US</country>
          <state>WA</state>
          <city>Bellingham</city>
          <gps>
            <longitude>-122.499225</longitude>
            <latitude>48.759553</latitude>
          </gps>
        </location>
        <age>45</age>
        <employDate>2009-06-01</employDate>
        <skills>
          <skill>powerpoint</skill>
          <skill>photoshop</skill>
        </skills>
      </employee>

      <employee>
        <name>Mike</name>
        <sex>Male</sex>
        <organization>Sales</organization>
        <location>
          <country>US</country>
          <state>Oregan</state>
          <city>Eugene</city>
          <gps>
            <longitude>-123.086754</longitude>
            <latitude>44.052069</latitude>
          </gps>
        </location>
        <age>55</age>
        <employDate>1999-06-01</employDate>
        <skills>
          <skill>powerpoint</skill>
          <skill>negotiation</skill>
        </skills>
      </employee>

    </sample>

    let $employees := $data/employee

    (: The facet definitions :)

    (: organization facet ordered by name ascending :)
    let $org-facet :=
        <facet-def>
          <name>Org</name>
          <group-by>/organization</group-by>
          <limit>100</limit>
          <order-by direction="ascending">name</order-by>
        </facet-def>

    (: sex facet ordered by count descending :)
    let $sex-facet :=
        <facet-def>
          <name>Sex</name>
          <group-by>/sex</group-by>
          <limit>100</limit>
          <order-by direction="descending">count</order-by>
        </facet-def>

    (: skill (repeatable values) facet by count descending :)
    let $skill-facet :=
        <facet-def>
          <name>Skill</name>
          <group-by>//skill</group-by>
          <order-by direction="descending">count</order-by>
        </facet-def>

    (: hierarchical location facet by country/state/city :)
    let $location-facet :=
        <facet-def>
          <name>Country</name>
          <group-by>/location/country</group-by>
          <facet-def>
            <name>State</name>
            <group-by>/location/state</group-by>
            <facet-def>
              <name>City</name>
              <group-by>/location/city</group-by>
            </facet-def>
          </facet-def>
        </facet-def>

    (: custom facet by employment year :)
    let $year-facet :=
        <facet-def>
          <name>Employ year</name>
          <group-by
            pred="local:group-by-year"
            drill="local:drill-by-year">
            /employDate</group-by>
        </facet-def>

    (: custom facet by age range:)
    let $age-facet :=
        <facet-def>
          <name>Employ year</name>
          <group-by
            pred="local:group-by-age-range"
            drill="local:drill-by-age-range">
            /age</group-by>
        </facet-def>

    (: custom hierarchical facet of state/skills :)
    let $state-skills-facet :=
        <facet-def>
          <name>State</name>
          <group-by>/location/state</group-by>
          <facet-def>
              <name>Skills</name>
              <group-by>/skills/skill</group-by>
          </facet-def>
        </facet-def>

    (: custom geo location facet :)
    let $region-facet :=
        <facet-def>
            <name>Region</name>
            <group-by
              pred="local:group-by-region"
              drill="local:drill-by-region">
              /location/gps</group-by>
        </facet-def>

    return
      <result>
      <facets>{
        facet:count($employees,
            ($org-facet, $sex-facet, $location-facet, $skill-facet,
             $year-facet, $age-facet, $state-skills-facet, $region-facet) )
      }</facets>
      <drill-by-sales-sex>{
        for $e in $employees[ facet:filter(., $org-facet, "Sales") and facet:filter(., $sex-facet, "Female") ]
        return $e/name
      }</drill-by-sales-sex>
      <drill-by-age-range-twentyplus>{
        for $e in $employees[ facet:filter(., $age-facet, "20+")  ]
        return $e/name
      }</drill-by-age-range-twentyplus>
      <drill-by-region-south>{
        for $e in $employees[ facet:filter(., $region-facet, "Southern US")  ]
        return $e/name
      }</drill-by-region-south>
      </result>


Expected output:

    <result>
    <facets>
        <facet name="Org">
            <value name="Finance">1</value>
            <value name="HR">2</value>
            <value name="Sales">3</value>
        </facet>
        <facet name="Sex">
            <value name="Male">4</value>
            <value name="Female">2</value>
        </facet>
        <facet name="Country">
            <value name="US">6
                <facet name="State">
                    <value name="WA">3
                        <facet name="City">
                            <value name="Bellingham">2</value>
                            <value name="Seattle">1</value>
                        </facet>
                    </value>
                    <value name="CA">2
                        <facet name="City">
                            <value name="San Francisco">1</value>
                            <value name="Pleasanton">1</value>
                        </facet>
                    </value>
                    <value name="Oregan">1
                        <facet name="City">
                            <value name="Eugene">1</value>
                        </facet>
                    </value>
                </facet>
            </value>
        </facet>
        <facet name="Skill">
            <value name="powerpoint">4</value>
            <value name="word">4</value>
            <value name="excel">2</value>
            <value name="photoshop">1</value>
            <value name="openoffice">1</value>
            <value name="linux">1</value>
            <value name="negotiation">1</value>
            <value name="windows">1</value>
        </facet>
        <facet name="Employ year">
            <value name="2009">1</value>
            <value name="2010">3</value>
            <value name="2003">1</value>
            <value name="1999">1</value>
        </facet>
        <facet name="Employ year">
            <value name="<20">1</value>
            <value name="30+">1</value>
            <value name="20+">2</value>
        </facet>
        <facet name="State">
            <value name="WA">3
                <facet name="Skills">
                    <value name="photoshop">1</value>
                    <value name="openoffice">1</value>
                    <value name="powerpoint">2</value>
                    <value name="word">2</value>
                </facet>
            </value>
            <value name="CA">2
                <facet name="Skills">
                    <value name="linux">1</value>
                    <value name="powerpoint">1</value>
                    <value name="excel">2</value>
                    <value name="word">2</value>
                    <value name="windows">1</value>
                </facet>
            </value>
            <value name="Oregan">1
                <facet name="Skills">
                    <value name="negotiation">1</value>
                    <value name="powerpoint">1</value>
                </facet>
            </value>
        </facet>
        <facet name="Region">
            <value name="Southern US">2</value>
            <value name="Northern US">4</value>
        </facet>
    </facets>
    <drill-by-sales-sex>
        <name>Kylie</name>
    </drill-by-sales-sex>
    <drill-by-age-range-twentyplus>
        <name>John Doe</name>
        <name>Kylie</name>
    </drill-by-age-range-twentyplus>
    <drill-by-region-south>
        <name>John Doe</name>
        <name>Jane Joe</name>
    </drill-by-region-south>
    </result>