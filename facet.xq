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

    (: Customized group-by predicates, come in pairs, another one for drill :)
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
    declare function local:drill-by-region($gps as node(), $value as xs:string) as xs:boolean {
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

    let $org-facet :=
        <facet-def>
          <name>Org</name>
          <group-by>/organization</group-by>
          <limit>100</limit>
          <order-by direction="ascending">name</order-by>
        </facet-def>

    let $sex-facet :=
        <facet-def>
          <name>Sex</name>
          <group-by>/sex</group-by>
          <limit>100</limit>
          <order-by direction="descending">count</order-by>
        </facet-def>

    let $skill-facet :=
        <facet-def>
          <name>Skill</name>
          <group-by>//skill</group-by>
          <order-by direction="descending">count</order-by>
        </facet-def>

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

    let $year-facet :=
        <facet-def>
          <name>Employ year</name>
          <group-by
            pred="local:group-by-year"
            drill="local:drill-by-year">
            /employDate</group-by>
        </facet-def>

    let $age-facet :=
        <facet-def>
          <name>Employ year</name>
          <group-by
            pred="local:group-by-age-range"
            drill="local:drill-by-age-range">
            /age</group-by>
        </facet-def>

    let $state-skills-facet :=
        <facet-def>
          <name>State</name>
          <group-by>/location/state</group-by>
          <facet-def>
              <name>Skills</name>
              <group-by>/skills/skill</group-by>
          </facet-def>
        </facet-def>

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
