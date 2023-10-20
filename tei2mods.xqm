xquery version "3.1";
(:
: Module Name: TEI to MODS
: Module Version: 1.0
: Copyright: GNU General Public License v3.0
: Proprietary XQuery Extensions Used: None
: XQuery Specification: 21 March 2017
: Module Overview: This module contains functions for converting a tei:biblStruct
:                  element into a MODS bibliography record.
:)

(:~ 
: This module provides the functions that convert a tei:biblStruct element into a
: MODS bibliography record. Originally implemented to support Syriaca.org's data
: pipeline between the Srophe App and Zotero database. As such, some functionality is
: limited by what the Zotero translator supports.
:
: @author William L. Potter
: @version 1.0
:)
module namespace tei2mods="http://wlpotter.github.io/ns/tei2mods";

import module namespace functx="http://www.functx.com";

declare namespace mods="http://www.loc.gov/mods/v3";
declare namespace tei="http://www.tei-c.org/ns/1.0";

declare variable $tei2mods:teins := "http://www.tei-c.org/ns/1.0";
declare variable $tei2mods:modsns := "http://www.loc.gov/mods/v3";

declare variable $tei2mods:default-type-of-resource := 
    element {QName($tei2mods:modsns, "typeOfResource")} {"text"};


(:~
: Converts a single tei:biblStruct element to a MODS record.
: 
: @param $biblStruct the tei:biblStruct element to be converted.
: 
: @return a MODS bibliographic record corresponding to the $biblStruct
:)
declare function tei2mods:convert-biblStruct-to-mods($biblStruct as node())
as node()
{
    let $analytic := tei2mods:convert-analytic-to-mods($biblStruct/tei:analytic, $biblStruct/tei:monogr[1]/tei:title[1]/@level/string())

    let $series := tei2mods:convert-series-to-mods($biblStruct/tei:series[1])


    let $mods := 
        if($analytic) then tei2mods:convert-monogr-to-mods($biblStruct/tei:monogr[1], $series, $analytic)
        else tei2mods:convert-monogr-to-mods($biblStruct/tei:monogr[1], $series)

    let $processedIdnos := tei2mods:convert-idnos-to-mods($biblStruct//tei:idno)

    return element {QName($tei2mods:modsns, "mods")} {
        $mods/*[name() != "relatedItem"],
        $processedIdnos,
        $mods/mods:relatedItem
    }
};

declare function tei2mods:convert-analytic-to-mods($analytic as node()?, $monogrType as xs:string)
as node()?
{
    if(not($analytic)) then ()
    else
        let $titleInfo := tei2mods:convert-titles-to-mods($analytic/tei:title)

        let $typeOfResource := $tei2mods:default-type-of-resource (:might not need assignment...:)

        let $genre := 
            switch($monogrType)
            case "j" return tei2mods:create-mods-genre("journalArticle", "local")
            case "m" return tei2mods:create-mods-genre("bookSection", "local")
            default return ()

        let $names := tei2mods:convert-contributors-to-mods(($analytic/tei:author, $analytic/tei:editor))

    return
        element {QName($tei2mods:modsns, "mods")} {
            $titleInfo,
            $typeOfResource,
            $genre,
            $names
        }
};

declare function tei2mods:convert-series-to-mods($series as node()?)
as node()?
{
    if(not($series)) then ()
    else
        let $titles := tei2mods:convert-titles-to-mods($series/tei:title)

        let $seriesNum := 
            if($series/tei:biblScope) then
                element {QName($tei2mods:modsns, "part")} {
                    element {QName($tei2mods:modsns, "detail")} {
                        attribute {"type"} {"volume"},
                        element {QName($tei2mods:modsns, "number")} {
                            $series/tei:biblScope/text()
                        }
                    }
                }
            else ()
        
        let $contributors := tei2mods:convert-contributors-to-mods($series/tei:editor) 

        return 
        element {QName($tei2mods:modsns, "relatedItem")} {
            attribute {"type"} {"series"},
            $titles,
            $contributors,
            $seriesNum
        }
};

(:~
: Convert a tei:monogr that includes an analytic level to a mods record (i.e., the monogr becomes a relatedItem[@type="host"])
:)
declare function tei2mods:convert-monogr-to-mods($monogr as node(), $seriesMods as node()?, $analyticMods as node())
as node()
{
    (: create a temporary mods record for the monographic portion of the record :)
    let $monogrMods := tei2mods:convert-monogr-to-mods($monogr, $seriesMods)

    let $monogrRelatedItem :=
        element {QName($tei2mods:modsns, "relatedItem")} {
            attribute {"type"} {"host"},
            $monogrMods/*[not(name() = "language")][not(name() = "typeOfResource")] (: all elements except the language :)
        }
    
    return 
        element {QName($tei2mods:modsns, "mods")} {
            $analyticMods/*,
            $monogrMods/mods:language,
            $monogrRelatedItem
        }
};

(:! NOTE. Turns out Syriaca bibls can have more than one monogr element. I hate that. Working under the assumption that there's just one so I don't have to deal with it. Will catch errors in a report and hopefully it's small enough that we can do by hand. :)
declare function tei2mods:convert-monogr-to-mods($monogr as node(), $seriesMods as node()?)
as node()
{
    let $titleInfo := tei2mods:convert-titles-to-mods($monogr/tei:title)
    let $typeOfResource := $tei2mods:default-type-of-resource (:might not need assignment...:)

    let $genre := 
        switch($monogr/tei:title[1]/@level/string())
        case "j" return tei2mods:create-mods-genre("journal", "margt")
        case "m" return (tei2mods:create-mods-genre("book", "local"), tei2mods:create-mods-genre("book", "marcgt"))
        default return ()

    let $names := tei2mods:convert-contributors-to-mods(($monogr/tei:author, $monogr/tei:editor))
    (: extract the series editor info from series MODS :)
    let $seriesNames := $seriesMods/mods:name
    let $names := ($names, $seriesNames)
    
    let $extent := if($monogr/tei:extent) then
        element {QName($tei2mods:modsns, "physicalDescription")} {
            element {QName($tei2mods:modsns, "extent")} {
                $monogr/tei:extent/text()
            }
        }
        else ()
    
    let $volInfo := 
        if($monogr/tei:biblScope[@unit="vol" or unit="tomus"]) then
            element {QName($tei2mods:modsns, "detail")} {
                attribute {"type"} {"volume"},
                element {QName($tei2mods:modsns, "number")} {
                    $monogr/tei:biblScope[@unit="vol"]/text()
                }
            }
        else ()
    
    let $issueInfo := 
        if($monogr/tei:biblScope[@unit="issue"]) then
            element {QName($tei2mods:modsns, "detail")} {
                attribute {"type"} {"issue"},
                element {QName($tei2mods:modsns, "number")} {
                    $monogr/tei:biblScope[@unit="issue"]/text()
                }
            }
        else ()
    
    let $pageRange :=
        if($monogr/tei:biblScope[@unit="page" or @unit="pp" or @unit="col"]) then
            element {QName($tei2mods:modsns, "extent")} {
                attribute {"unit"} {"pages"},
                element {QName($tei2mods:modsns, "list")} {
                    $monogr/tei:biblScope[@unit="page" or @unit="pp" or @unit="col"]//text()
                    => string-join(" ")
                    => normalize-space()
                }
            }
        else ()

    let $part :=
        if($volInfo or $issueInfo or $pageRange) then
            element {QName($tei2mods:modsns, "part")} {
                $volInfo, $issueInfo, $pageRange
            }
        else ()
        
    let $originInfo := 
         element {QName($tei2mods:modsns, "originInfo")} {
            if($monogr/tei:edition) then
                element {QName($tei2mods:modsns, "edition")} {
                    $monogr/tei:edition/text()
                }
            else (),
            element {QName($tei2mods:modsns, "place")} {
                element {QName($tei2mods:modsns, "placeTerm")} {
                    attribute {"type"} {"text"},
                    $monogr/tei:imprint/tei:pubPlace//text()
                        => string-join(" ")
                        => normalize-space()
                }
            },
            element {QName($tei2mods:modsns, "publisher")} {
                $monogr/tei:imprint/tei:publisher/text()
            },
            element {QName($tei2mods:modsns, "copyrightDate")} {
                $monogr/tei:imprint/tei:date/text()
            },
            element {QName($tei2mods:modsns, "issuance")} {
                switch($monogr/tei:title[1]/@level/string())
                case "j" return "continuing"
                case "m" return "monographic"
                default return ()
            }
        }
    let $language := 
        if($monogr/tei:textLang) then
            for $langAttr in $monogr/tei:textLang/@*
            order by $langAttr (: mainLang attribute goes first :)
            return 
                element {QName($tei2mods:modsns, "language")} {
                    element {QName($tei2mods:modsns, "languageTerm")} {
                        attribute {"type"} {"text"},
                        $langAttr/string()
                    }
                }
        else ()
    return 
        element {QName($tei2mods:modsns, "mods")} {
        $titleInfo,
        $typeOfResource,
        $genre,
        $names,
        $extent,
        $part,
        $originInfo,
        $language,
        functx:remove-elements($seriesMods, "name")
    }
};
(:~
: Convert a series of tei:title elements into mods:titleInfo elements
:
: @param $titles is a sequence of tei:title elements
:
: Returns a mods:titleInfo element for each of the titles in the $titles parameter.
: Applies a @type attribute of "abbreviated" to tei:titles typed as "short".
:
: Currently ignores sub elements of the tei:titles
:)
declare function tei2mods:convert-titles-to-mods($titles as node()*)
as node()*
{
    for $title in $titles
    let $titleText := $title//text() (: for now, ignore the sub-elements...:)
    let $titleText := string-join($titleText, " ") => normalize-space()

    let $shortTitleAttr := 
        if($title/@type = "short") then
            attribute {"type"} {"abbreviated"}
        else ()
    
    return element {QName($tei2mods:modsns, "titleInfo")}
        {
            $shortTitleAttr,
            element {QName($tei2mods:modsns, "title")} {
                $titleText
            }
        }
};

(:
:)
declare function tei2mods:convert-contributors-to-mods($contributors as node()*) 
as node()*
{
    for $contr in $contributors
    let $marcrelatorTerm := 
        if ($contr/name() = "author") then "aut"
        else if($contr/../name() = "series") then "pbd"
        else if($contr/@role/string() = "translator") then "trl"
        else "edt"
    let $role :=
        element {QName($tei2mods:modsns, "role")} {
            element {QName($tei2mods:modsns, "roleTerm")} {
                attribute {"type"} {"code"},
                attribute {"authority"} {"marcrelator"},
                $marcrelatorTerm
            }
        }

    (: if there is a persName, there could be multiple, so pass all to create individual name elements :)
    return 
        if($contr/tei:persName) then
            for $pn in $contr/tei:persName 
            return tei2mods:create-mods-name($pn/*, $role, $pn/@xml:lang/string())
        else
            tei2mods:create-mods-name($contr/*, $role, $contr/@xml:lang/string())
};

(:~
: Create a mods:name element based on the name info found in a tei:author or tei:editor element.
: Passes the already established role info from conver-tcontributors-to-mods, as well as the xml:lang of the name if available
:)
declare function tei2mods:create-mods-name($names as node()*, $role as node(), $lang as xs:string?)
as node()*
{
    (: using type 'corporate' is a Zotero ingest hack to ensure it doesn't create multiple name fields :)
    let $nameType := if($names/descendant-or-self::tei:name) then "corporate" else "personal"
    
    let $nameParts := 
        if($names/descendant-or-self::tei:name) then
            element {QName($tei2mods:modsns, "namePart")} {
                $names//text() => string-join(" ") => normalize-space()
            }
        else
            let $forenames := $names[name() = "forename"]
            let $middleInitials := $names[name() = "addName"][@type="middle-initial"]
            let $untaggedTitles := $names[name() = "addName"][@type="untagged-title"]
            let $untypedAddNames := $names[name() = "addName"][not(@type)]
            let $familyNames := $names[name() = "addName"][@type="family"]
            let $surnames := $names[name() = "surname"]

            let $givenNameString := ($forenames/text(), $middleInitials/text(), $untaggedTitles/text(), $untypedAddNames/text())
                => string-join(" ")
                => normalize-space()
            let $givenNames := 
                element {QName($tei2mods:modsns, "namePart")} {
                    attribute {"type"} {"given"},
                    $givenNameString
                }
            
            let $familyNameString := ($familyNames/text(), $surnames/text())
                => string-join(" ")
                => normalize-space()
            let $familyNames :=
                element {QName($tei2mods:modsns, "namePart")} {
                    attribute {"type"} {"family"},
                    $familyNameString
                }
            return ($givenNames, $familyNames)

    return 
        element {QName($tei2mods:modsns, "name")} {
            attribute {"type"} {$nameType},
            if($lang != "") then attribute {"lang"} {$lang} else (),
            $nameParts,
            $role
        }
};

declare function tei2mods:create-mods-genre($term as xs:string, $authority as xs:string)
as node()
{
    element {QName($tei2mods:modsns, "genre")} {
        attribute {"authority"} {$authority},
        $term
    }
};

declare function tei2mods:convert-idnos-to-mods($idnos as node()+)
as node()+
{
    let $els :=
        for $idno in $idnos
        return 
            switch($idno/@type/string())
            case "ISBN" return element {QName($tei2mods:modsns, "identifier")} {attribute {"type"} {"isbn"}, $idno/text()}
            case "ISSN" return element {QName($tei2mods:modsns, "identifier")} {attribute {"type"} {"issn"}, $idno/text()}
            case "callNumber" return element {QName($tei2mods:modsns, "classification")} {attribute {"authorityURI"} {"http://id.loc.gov/vocabulary/classSchemes/lcc"}, $idno/text()}
            case "URI" return tei2mods:process-uri($idno)
            default return ()
    
    let $extraData := $els/self::*[name() = "extra"]
    let $extraData :=
        for $e in $extraData
        return $e/@key/string()||": "||$e/text()
    let $extraData := string-join($extraData, "\n")
    let $extraNote := 
        element {QName($tei2mods:modsns, "note")} {
            attribute {"type"} {"extra"},
            $extraData
        }
    return ($els/self::*[name() != "extra"], $extraNote)
};

(:Returns either a mods:identifer, mods:location/mods:url, or an extra element 
: The latter will be used to create the 'extra' field on zotero import :)
declare function tei2mods:process-uri($idno as node())
as node()?
{
    if(contains($idno/text(), "dx.doi")) then
        element {QName($tei2mods:modsns, "identifier")}
        {
            attribute {"type"} {"doi"},
            $idno/text() => substring-after("dx.doi.org/")
        }
    else if(contains($idno/text(), "worldcat")) then
        element {"extra"} {
            attribute {"key"} {"OCLC"},
            $idno/text() => substring-after("oclc/")
        }
    else if (contains($idno/text(), "syriaca")) then
        element {"extra"} {
            attribute {"key"} {"deprecated"},
            $idno/text()
        }
    else 
        element {QName($tei2mods:modsns, "location")}
        {
            element {QName($tei2mods:modsns, "url")} {
                attribute {"usage"} {"primary"},
                $idno/text()
            }
        }
};