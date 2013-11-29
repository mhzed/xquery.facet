
# Proposal to add faceted search support in XQuery 3.1

## Introduction

Faceted search has proven to be enormously popular in real world applications.  This document proposes a potential
solution that will facilitate the implementation of faceted search in XQuery.

In its essence, faceted search refers to aggregating (counting) search results based on (dynamic or static) values of
one or more fields.  The aggregating function is similar to "group by" clause introduced in XQuery 3.0.  In fact,
this document will demonstrate via implementation example that the faceted count can be implemented entirely using
"group by" clause.  Nevertheless, we feel the solution presented here is still necessary for performance consideration
and syntactic clarity.

## Proposal

The proposal is to introduce the addition of two new built-in functions:

### fn:facet-count

#### Signature

    declare function fn:facet-count($results as node()*) as element(count)*
    declare function fn:facet-count($results as node()*, $byFunc as function(node()) as xs:string*) as element(count)*

#### Properties

    Both forms of this function are: non-deterministic, context-independent, focus-independent

#### Rules

    Given a sequence of nodes, and an optional unary predicate that returns a sequence of facet values for each node,
    count the number of occurrences of each facet value.

#### Example

    Both forms of function can be implemented below via XQuery:

    (: form 1 :)
    declare function local:facet-count(
        $results as node()*
    ) as element(count)* {

      let $asIs := function ($e as node()) as xs:string { $e }
      return local:facet-count($results, $asIs)
    };

    (: form 2 :)
    declare function local:facet-count(
        $results as node()*,
        $byFunc as function(node()) as xs:string*
    ) as element(count)* {

      let $expandSeq :=
        for $r in $results
        for $v in $byFunc($r)
        return <r>{$v}</r>

      for $e in $expandSeq
      let $val := data($e)
      group by $val
      return
        <count value="{$val}">
          {count($e)}
        </count>
    };

### fn:nested-facet-count

#### Signature

    declare function fn:nested-facet-count(
        $results as node()*,
        $byFuncs as (function(node()) as xs:string*)*
    ) as element(count)*


#### Properties

    This function is: non-deterministic, context-independent, focus-independent

#### Rules

    Given a sequence of nodes, and a sequence of unary predicates that returns a sequence of facet values for each node,
    with the lower indexed predicate producing the outer facets, count the nested facets.  See example below.

#### Example

    The implementation in XQuery:

    declare function local:nested-facet-count(
        $results as node()*,
        $byFuncs as (function(node()) as xs:string*)*
    ) as element(count)* {

      if (count($byFuncs)=0) then ()
      else
        let $expandSeq :=
          for $r in $results
          for $v in $byFuncs[1]($r)
          return <r>{$v}{$r}</r>

        for $e in $expandSeq
        let $val := $e/text()
        group by $val
        return
          <count value="{$val}">
            { count($e) }
            {
              (: strictly speaking, if $results is a sequence of non-element nodes, following line will not work,
                 however such limitation should not exist for the underlying XQuery engine implementation :)
              local:nested-facet-count($e/*, subsequence($byFuncs, 2))
            }
          </count>
    };


## Performance considerations

In real world application, facet count is usually calculated over a large set of results.  For example,
on a shopping site, a user enters a full text search query that returns 20000 products.  Even though only 10 products
are retrieved and shown in the page, the facets are always counted over the entire 20000 products.  As such, performance
is critical for facet counting.

The facet-count function above can be implemented in O(n) with minimal memory footprint.  Below we will illustrate a
sample implementation in python:

    def facet_count(sequence, predicate):
        countMap = {}
        for e in sequence:
            for facet in predicate(e):
                if countMap.has_key(facet):
                    countMap[facet] = countMap[facet] + 1
                else:
                    countMap[facet] = 1
        return countMap

Comparing to the "group by" solution offered in examples above, this implementation does not require sorting, and
is therefore faster.

Similarly, nested-facet-count can be implemented as follows, in O(n):

    def nested_facet_count(sequence, predicates):
        def _nested_facet_count_elem(countMap, elem, predicates):
            if len(predicates) > 0:
                for facet in predicates[0](elem):
                    if countMap.has_key(facet):
                        countMap[facet]["n"] = countMap[facet]["n"] + 1
                    else:
                        countMap[facet] = { "n": 1, "_nest": {} }
                    _nested_facet_count_elem(countMap[facet]['_nest'], elem, predicates[1:])
        countMap = {}
        for e in sequence:
            _nested_facet_count_elem(countMap, e, predicates)
        return countMap


### Database performance consideration

In the context of a XML database, the facet-counted fields do not need to be pre-indexed, however they should be
"covered" in index (Covering index).  This optimization is critical as otherwise facet count will result in lots
of random disk IO.

## Use cases

Below is the sample xml data used to demonstrate use cases, expressed in XQuery:

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

### Case 1

Count employees by organization, show results ordered by organization name.

XQuery code:

    <facet value="Organization">
      {
        for $c in fn:facet-count($employees/organization) order by $c/@value ascending return $c
      }
    </facet>

Expect results:

    <facet value="Organization">
        <count value="Finance">1</count>
        <count value="HR">2</count>
        <count value="Sales">3</count>
    </facet>

### Case 2

Count employees by sex, order by count.

XQuery code:

    <facet value="Sex">
      {
        for $c in fn:facet-count($employees/sex) order by xs:integer($c) descending return $c
      }
    </facet>

Expect results:

    <facet value="Sex">
        <count value="Male">4</count>
        <count value="Female">2</count>
    </facet>

### Case 3

Count employee age by numeric range, order by count.

XQuery code:

    <facet value="Age">
      {
        let $byAgeRange := function($e as node()) as xs:string {
          let $n := xs:integer(data($e))
          return
            if ($n < 20) then "<20"
            else if ($n < 30) then "20+"
            else if ($n < 40) then "30+"
            else if ($n < 50) then "40+"
            else ">50"
        }
        for $c in fn:facet-count($employees/age, $byAgeRange) order by $c descending return $c
      }
    </facet>

Expect results:

    <facet value="Age">
        <count value="20+">2</count>
        <count value="40+">1</count>
        <count value="30+">1</count>
        <count value="&lt;20">1</count>
        <count value=">50">1</count>
    </facet>

### Case 4

Count employee age with more descriptive facets, no order.

XQuery code:

    <facet value="Age with description">
      {
        let $byAgeRange := function($e as node()) as xs:string* {
          let $n := xs:integer(data($e))
          return
            if ($n < 20) then "teenager"
            else if ($n < 40) then ()   (: do not count :)
            else if ($n < 50) then "middle-aged"
            else ("older", "near retirement") (: count as both :)
        }
        return fn:facet-count($employees/age, $byAgeRange)
      }
    </facet>

Expect results:

    <facet value="Age with description">
        <count value="teenager">1</count>
        <count value="middle-aged">1</count>
        <count value="older">1</count>
        <count value="near retirement">1</count>
    </facet>

### Case 5

Count by employment year.

XQuery code:

    <facet value="Employ Year">
      {
        let $byYear := fn:substring(?, 1, 4)
        return fn:facet-count($employees/employDate, $byYear)
      }
    </facet>

Expect results:

    <facet value="Employ Year">
        <count value="2010">3</count>
        <count value="2003">1</count>
        <count value="2009">1</count>
        <count value="1999">1</count>
    </facet>

### Case 6

Count by repeatable skill values

XQuery code:

     <facet value="Skills">
      {
        fn:facet-count($employees, function($e as node()) as xs:string+ { $e//skill })
        (: or alternatively:  fn:facet-count($employees//skill) :)
      }
    </facet>

Expect results:

    <facet value="Skills">
        <count value="word">4</count>
        <count value="excel">2</count>
        <count value="windows">1</count>
        <count value="powerpoint">4</count>
        <count value="linux">1</count>
        <count value="openoffice">1</count>
        <count value="photoshop">1</count>
        <count value="negotiation">1</count>
    </facet>

### Case 7

Count by country/state/city.

XQuery code:

    <facet value="Location">
      {
        let $byLocationHierarchy :=
          (function($e as node()) as xs:string+ { $e/country },
           function($e as node()) as xs:string+ { $e/state },
           function($e as node()) as xs:string+ { $e/city })
        return fn:nested-facet-count($employees/location, $byLocationHierarchy)
      }
    </facet>

Expect results:

    <facet value="Location">
        <count value="US">6
            <count value="CA">2
                <count value="Pleasanton">1</count>
                <count value="San Francisco">1</count>
            </count>
            <count value="WA">3
                <count value="Seattle">1</count>
                <count value="Bellingham">2</count>
            </count>
            <count value="Oregan">1
                <count value="Eugene">1</count>
            </count>
        </count>

### Case 8

Count by state/skills: nested facet count with repeatable values

XQuery code:

    <facet value="State/Skills">
      {
        let $byStateSkill :=
          (function($e as node()) as xs:string+ { $e/location/state },
           function($e as node()) as xs:string+ { $e//skill })
        return fn:nested-facet-count($employees, $byStateSkill)
      }
    </facet>

Expected results:

    <facet value="State/Skills">
        <count value="CA">2
            <count value="word">2</count>
            <count value="excel">2</count>
            <count value="windows">1</count>
            <count value="powerpoint">1</count>
            <count value="linux">1</count>
        </count>
        <count value="WA">3
            <count value="openoffice">1</count>
            <count value="word">2</count>
            <count value="powerpoint">2</count>
            <count value="photoshop">1</count>
        </count>
        <count value="Oregan">1
            <count value="powerpoint">1</count>
            <count value="negotiation">1</count>
        </count>
    </facet>

### Case 9

Geo-distance facets

XQuery code:

    <facet value="Distance">
      {
        (: lets assume there is a function that calculates distance between lat/long in kilometers :)
        declare function geo:distance(lat1 as xs:decimal, long1 as xs:decimal, lat2 as xs:decimal, long2 as xs:decimal)
                         as xs:decimal external;
        let $distanceFromHere := geo:distance(37.0625, -95.677068, ?, ?)
        let $byDistance := function($e as node()) as xs:string {
            let $distance := $distanceFromHere($e//latitude, $e//longitude)
            return
              if ($distance < 2.0) then "<2km"
              else if ($distance < 10.0) then "2-10km"
              else ">10km"
        }
        return fn:facet-count($employees, $byDistance)
      }
    </facet>

Expected results:

    <facet value="Distance">
        <count value="<2km">1</count>
        <count value="2-10km">1</count>
        <count value=">10km">4</count>
    </facet>
