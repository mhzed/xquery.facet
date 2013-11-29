
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

declare function local:facet-count(
    $results as node()*
) as element(count)* {

  let $getText := function ($e as node()) as xs:string { $e/text() }
  return local:facet-count($results, $getText)
};


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
        { local:nested-facet-count($e/*, subsequence($byFuncs, 2)) }
      </count>
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

return
  <facets>
    <facet value="Organization">
      { (: facet counted by value ordered by value :)
        for $c in local:facet-count($employees/organization) order by $c/@value ascending return $c
      }
    </facet>
    <facet value="Sex">
      { (: facets counted by value ordered by frequency :)
        for $c in local:facet-count($employees/sex) order by xs:integer($c) descending return $c
      }
    </facet>
    <facet value="Age">
      { (: facets counted by customized numeric range ordered by frequency :)
        let $byAgeRange := function($e as node()) as xs:string {
          let $n := xs:integer(data($e))
          return
            if ($n < 20) then "<20"
            else if ($n < 30) then "20+"
            else if ($n < 40) then "30+"
            else if ($n < 50) then "40+"
            else ">50"
        }
        for $c in local:facet-count($employees/age, $byAgeRange) order by $c descending return $c
      }
    </facet>
    <facet value="Age with description">
      { (: an more flexible facet by age:)
        let $byAgeRange := function($e as node()) as xs:string* {
          let $n := xs:integer(data($e))
          return
            if ($n < 20) then "teanager"
            else if ($n < 30) then ()   (: do not count :)
            else if ($n < 40) then ()
            else if ($n < 50) then "middle-aged"
            else ("older", "near retirement") (: count as both :)
        }
        return local:facet-count($employees/age, $byAgeRange)
      }
    </facet>
    <facet value="Employ Year">
      { (: facets counted by year :)
        let $byYear := fn:substring(?, 1, 4)
        return local:facet-count($employees/employDate, $byYear)
      }
    </facet>
    <facet value="Skills">
      { (: facets counted on expanded repeatable values :)
        local:facet-count($employees//skill)
      }
    </facet>
    <facet value="Skills">
      { (: facets counted on repeatable values :)
        local:facet-count($employees, function($e as node()) as xs:string+ {
          data($e//skill)
        })
      }
    </facet>
    <facet value="Location">
      { (: hierarchy facets sample :)
        let $byLocationHierarchy :=
          (function($e as node()) as xs:string+ { $e/country },
           function($e as node()) as xs:string+ { $e/state },
           function($e as node()) as xs:string+ { $e/city })
        return local:nested-facet-count($employees/location, $byLocationHierarchy)
      }
    </facet>
    <facet value="State/Skills">
      { (: hierarchy facets with repeatable values sample :)
        let $byLocationHierarchy :=
          (function($e as node()) as xs:string+ { $e/location/state },
           function($e as node()) as xs:string+ { $e//skill })
        return local:nested-facet-count($employees, $byLocationHierarchy)
      }
    </facet>
    <facet value="Location">
      { (: hierarchy facets, with ordering :)
        let $byLocationHierarchy :=
          (function($e as node()) as xs:string+ { $e/location/state },
           function($e as node()) as xs:string+ { $e//skill })
        let $facet-counts := local:nested-facet-count($employees, $byLocationHierarchy)
        return
          for $stateCount in $facet-counts
          order by $stateCount/@value   (: order state alphabetically :)
          return
            <count value="{$stateCount/@value}">{$stateCount/text()}
            {
              for $skillCount in $stateCount/count
              order by xs:integer($skillCount)  (: order skill by count :)
              return $skillCount
            }
            </count>
      }
    </facet>

  </facets>

