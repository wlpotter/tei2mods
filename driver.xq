xquery version "3.1";


declare namespace mods="http://www.loc.gov/mods/v3";
declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace tei2mods="http://wlpotter.github.io/ns/tei2mods" at "tei2mods.xqm";

import module namespace functx="http://www.functx.com";


declare variable $local:teins := "http://www.tei-c.org/ns/1.0";

declare variable $local:in-coll :=
    collection("/home/arren/Documents/GitHub/srophe-app-data/data/bibl/tei/");

declare variable $local:path-to-csv := "tei-only.csv";


declare variable $local:record-list :=
    let $lines := file:read-text($local:path-to-csv)
    return tokenize($lines, "\n");

let $mods := 
    for $doc in $local:in-coll
    let $docUri := $doc//tei:publicationStmt/tei:idno/text() => substring-before("/tei")
    where functx:is-value-in-sequence($docUri, $local:record-list)
    
    let $bibl := $doc//tei:biblStruct
    return try { tei2mods:convert-biblStruct-to-mods($bibl) } 
    catch * { let $failure :=
            element {"failure"} {
              element {"code"} {$err:code},
              element {"description"} {$err:description},
              element {"value"} {$err:value},
              element {"module"} {$err:module},
              element {"location"} {$err:line-number||": "||$err:column-number},
              element {"additional"} {$err:additional},
              element {"docUri"} {document-uri($doc)}
            }
            return $failure }


let $failures := $mods/self::*[name() = "failure"]

let $modsColl := 
    element {QName($tei2mods:modsns, "modsCollection")} {
    $mods/self::*[name() = "mods"]
}

return (put($modsColl, "mods.xml"), update:output($failures))