breed [citizens citizen]
breed [mapping-citizens mapping-citizen]
breed [buses bus]
breed [mapping-buses mapping-bus]
breed [vertices vertex]
undirected-link-breed [edges edge]
undirected-link-breed [map-links map-link]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

globals[
  ;; configuration
  district-width
  district-length
  initial-people-num
  people-per-company
  people-per-residence
  ;; interaction
  mouse-was-down?
  ;; transportation
  person-speed             ;; person
  car-speed                ;; car
  bus-speed                ;; bus
  acceleration
  event-duration           ;; person: work and rest
  bus-duration             ;; bus: wait
  ;; game parameter
  money
  ;; patch-set
  roads
  intersections
  idle-estates
  residence-district
  company-district
  residences
  companies
  ;; patch
  global-origin-station
  global-terminal-station
]

citizens-own[
  ;; basic
  residence
  company
  has-car?
  ;; game
  earning-power
  ;; transportation
  trip-mode                ;; 1: car, 2: bus, 3: taxi
  speed
  path
  advance-distance
  still?
  time
]

buses-own [
  origin-station           ;; vertex
  terminal-station         ;; vertex
  ;; transportation
  trip-mode                ;; mode
  speed
  path
  advance-distance
  still?
  time
]

patches-own[
  land-type                ;; land, road, bus-stop, residence, company, idle-estate
  intersection?
  green-light-on?          ;; land-type = "road"
  capacity                 ;; land-type = "residence" or "company"
]

vertices-own [
  weight
  predecessor
]

edges-own [
  bus-route?
  cost
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Setup
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  setup-config
  setup-globals
  setup-patches
  setup-estates
  setup-map
  setup-citizens
  reset-ticks
end

to setup-config
  set district-width       7
  set district-length      7
  set initial-people-num   0      ;; TODO 20
  set people-per-company   5
  set people-per-residence 1
  set mouse-was-down?      false
end

to setup-globals
  set person-speed         0.05
  set car-speed            0.99
  set bus-speed            0.49
  set acceleration         0.099
  set event-duration       50
  set bus-duration         2
  set money                0
end

to setup-patches
  ask patches [
    set intersection? false
    set green-light-on? true
  ]
  ;; roads
  ask patches with [
    pxcor mod (district-width + 1) = 0 or pycor mod (district-length + 1) = 0
  ][
    set land-type "road"
  ]
  set roads patch-set patches with [land-type = "road"]
  ask roads [
    set pcolor gray + 4
  ]
  ;; intersections
  ask patches with [
    pxcor mod (district-width + 1) = 0 and pycor mod (district-length + 1) = 0
  ][
    set intersection? true
  ]
  set intersections patch-set patches with [intersection? = true]
  ;; traffic lights
  ask intersections [
    let right-patch patch-at  1  0
    let left-patch  patch-at -1  0
    let up-patch    patch-at  0  1
    let down-patch  patch-at  0 -1
    ifelse green-light-on? [
      if right-patch != nobody [ ask right-patch [set pcolor green] ]
      if left-patch  != nobody [ ask left-patch  [set pcolor green] ]
      if up-patch    != nobody [ ask up-patch    [set pcolor red  ] ]
      if down-patch  != nobody [ ask down-patch  [set pcolor red  ] ]
    ][
      if right-patch != nobody [ ask right-patch [set pcolor red  ] ]
      if left-patch  != nobody [ ask left-patch  [set pcolor red  ] ]
      if up-patch    != nobody [ ask up-patch    [set pcolor green] ]
      if down-patch  != nobody [ ask down-patch  [set pcolor green] ]
    ]
  ]
  ;; land
  ask patches with [land-type != "road"][
    set land-type "land"
    set pcolor brown + 2
  ]
  ;; idle estate
  ask patches with [
    any? neighbors with [land-type = "road"] and land-type = "land"
  ][
    set land-type "idle-estate"
  ]
  set idle-estates patch-set patches with [land-type = "idle-estate"]
  ask idle-estates [
    set pcolor brown + 3
  ]
  ;; residence-district
  set residence-district patch-set patches with [
    ((pxcor > max-pxcor / 2 or pxcor < (- max-pxcor / 2)) and
    (pycor > max-pycor / 2 or pycor < (- max-pycor / 2))) and
    (land-type = "idle-estate")
  ]
  ;; company-district
  set company-district patch-set patches with [
    ((pxcor < max-pxcor / 2) and (pxcor > (- max-pxcor / 2)) and
    (pycor < max-pycor / 2) and (pycor > (- max-pycor / 2))) and
    ((land-type = "idle-estate"))
  ]
end

to setup-estates
  let residence-num ceiling(initial-people-num / people-per-residence)
  let company-num   ceiling(initial-people-num / people-per-company  )
  ;; residences
  ask n-of residence-num residence-district[
    set land-type "residence"
  ]
  set residences patch-set patches with [land-type = "residence"]
  ask residences [
    set pcolor yellow
    set capacity 0
  ]
  ;; companies
  ask n-of company-num company-district[
    set land-type "company"
  ]
  set companies patch-set patches with [land-type = "company"]
  ask companies [
    set pcolor blue
    set capacity 0
  ]
end

to setup-map
  ;; initialize vertices
  ask roads [
    sprout-vertices 1 [hide-turtle]
  ]
  ask residences [
    sprout-vertices 1 [hide-turtle]
  ]
  ask companies [
    sprout-vertices 1 [hide-turtle]
  ]
  ;; initialize edges
  ask vertices [
    create-edges-with vertices-on neighbors4 with [land-type = "road"][
      set shape "dotted"
      set bus-route? false
      set cost 10
    ]
  ]
end

to setup-citizens
  set-default-shape citizens "person business"
  ask residences [
    sprout-citizens people-per-residence [
      ;; set company
      let my-company one-of companies with [capacity < people-per-company]
      ask my-company [ set capacity capacity + 1 ]

      ;; set basic properties
      set residence         one-of vertices-on patch-here
      set company           one-of vertices-on my-company
      set earning-power     5

      ;; set has-car?
      ifelse random 100 < 50 [
        set has-car? true
        set color    magenta
      ][
        set has-car? false
        set color    cyan
      ]

      ;; set transportation properties
      set speed             person-speed
      set advance-distance  0
      set still?            false
      set time              0

      ;; set trip-mode
      set-trip-mode

      ;; set path
      set path find-path residence company trip-mode

      ;; hatch mapping person
      let residence-heading 0
      let controller nobody

      face first path
      set residence-heading heading
      set controller        self
      hide-turtle           ;; debug

      hatch-mapping-citizens 1 [
        set shape          "person business"
        set color          color
        set heading        residence-heading
        rt 90
        fd 0.25
        lt 90
        create-map-link-with controller [tie]
        show-turtle
      ]

      ;; set shape
      set-moving-shape
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Transportation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to advance [len]
  ifelse (advance-distance > len) [
    fd len
    set advance-distance advance-distance - len
  ][
    fd advance-distance
    set advance-distance 0
  ]
end

to wait-passenger
  if trip-mode = 4 [
    set time   bus-duration
    set still? true
  ]
end

to set-speed [mode]
  ifelse (mode = 1)[
    set speed car-speed
  ][
    ifelse (mode = 2)[
      set speed person-speed
    ][
      ifelse (mode = 3)[
        set speed car-speed
      ][
        set speed bus-speed
      ]
    ]
  ]
end

to set-duration [mode]
  ifelse (mode = 4)[         ;; bus
    set time   bus-duration
  ][                         ;; person
    set time event-duration
  ]
  set still? true
end

to set-static-shape
  if breed = citizens [
    ask map-link-neighbors [
      set shape "person business"
    ]
  ]
end

to set-moving-shape
  if trip-mode = 1 [
    ask map-link-neighbors [
      set shape "car top"
    ]
  ]
end

to set-trip-mode
  if breed = citizens [
    ifelse has-car? [
      set trip-mode 1
    ][
      set trip-mode 2
    ]
  ]
end

to set-path
  let origin-point     nobody
  let terminal-point   nobody
  let mode             0
  ifelse breed = buses [
    set origin-point   origin-station
    set terminal-point terminal-station
    set mode           4
  ][
    set origin-point   residence
    set terminal-point company
    set-trip-mode
    set mode           trip-mode
  ]

  if (patch-here = [patch-here] of origin-point)[
    set path find-path origin-point terminal-point mode
  ]
  if (patch-here = [patch-here] of terminal-point)[
    set path find-path terminal-point origin-point mode
  ]
end

to move [mode]
  set-speed mode
  set advance-distance speed
  while [advance-distance > 0 and length path > 1] [
    let next-vertex first path
    if (distance next-vertex < 0.00001) [
      set path but-first path
      face first path
      set next-vertex first path
      wait-passenger
    ]
    ifelse not still? [
      advance distance next-vertex
    ][
      set advance-distance 0
    ]
  ]

  if (length path = 1)[
    while [advance-distance > 0 and length path = 1][
      let next-vertex first path
      ifelse (distance next-vertex < 0.00001) [  ;; arrived at destination
        set path []
        ;; wait
        set-duration mode
        ;; set default shape
        set-static-shape
        ;; set path
        set-trip-mode
        set-path
      ][
        advance distance next-vertex
      ]
    ]
  ]
end

to stay
  set time time - 1
  if (time = 0)[
    set still? false
    if breed = buses [
      if (patch-here = [patch-here] of origin-station or
        patch-here = [patch-here] of terminal-station) [
        lt 180
        ]
    ]
    if breed = citizens [
      lt 180
      face first path
      set-moving-shape
      if (patch-here = [patch-here] of company)[
        set money money + earning-power
      ]
    ]
  ]
end

to progress
  ask citizens [
    ifelse still? [
      stay
    ][
      move trip-mode
    ]
  ]
  ask buses [
    ifelse still? [
      stay
    ][
      move trip-mode
    ]
  ]
end

to go
  progress
  mouse-manager
  tick
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interaction
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to add-bus-stop
  ;; setup
  ask global-origin-station [
    set land-type "bus-stop"
  ]
  ask global-terminal-station [
    set land-type "bus-stop"
  ]
  let origin-station-vertex   one-of vertices-on global-origin-station
  let terminal-station-vertex one-of vertices-on global-terminal-station
  ;; Create bus line
  let bus-path find-path origin-station-vertex terminal-station-vertex 1
  let bus-line filter [ [node] ->
    ([intersection?] of [patch-here] of node = true) or
    node = terminal-station-vertex
  ] bus-path
  set bus-line fput origin-station-vertex bus-line
  let i 0
  while [i < length bus-line - 1][
    ask item i bus-line [
      create-edge-with item (i + 1) bus-line [
        set bus-route? true
        set cost length bus-line
        set color orange
        set thickness 0.2
      ]
    ]
    set i i + 1
  ]
  ;; Create bus
  ask global-origin-station [
    let bus-heading 0
    let controller nobody
    sprout-buses 1 [
      ;; set basic properties
      set origin-station   origin-station-vertex
      set terminal-station terminal-station-vertex
      ;; set transportation properties
      set speed            bus-speed
      set still?           false
      set time             0
      set trip-mode        4

      ;; set path
      set path             but-first bus-line

      ;; set parameters for the mapping bus
      face first path
      set bus-heading      heading
      set controller       self
      hide-turtle          ;; debug
    ]
    sprout-mapping-buses 1 [
      set shape            "bus"
      set color            orange
      set size             1.5
      set heading          bus-heading
      rt 90
      fd 0.25
      lt 90
      create-map-link-with controller [tie]
    ]
  ]
end

to-report mouse-clicked?
  report (mouse-was-down? = true and not mouse-down?)
end

to mouse-manager
  let mouse-is-down? mouse-down?
  if mouse-clicked? [
    let patch-clicked patch round mouse-xcor round mouse-ycor
    print "clicked!"  ;; debug
    if ([land-type] of patch-clicked = "road")[
      ifelse (not is-patch? global-origin-station) [
        set global-origin-station patch-clicked
        print patch-clicked  ;; log
      ][
        if (patch-clicked != global-origin-station)[
          set global-terminal-station patch-clicked
          print patch-clicked  ;; log
          add-bus-stop
          set global-origin-station  nobody
          set global-terminal-station nobody
        ]
      ]
    ]
  ]
  set mouse-was-down? mouse-is-down?
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Algorithm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Dijkstra
to initialize-single-source [ source ]
  ask vertices [
    set weight 10000  ;; positive infinity
    set predecessor nobody
  ]
  ask source [
    set weight 0
  ]
end

to relax [u v w]
  let new-weight ([weight] of u + [cost] of w)
  if [weight] of v > new-weight [
    ask v [
      set weight new-weight
      set predecessor u
    ]
  ]
end

to dijkstra [source target mode] ;; mode: 1: take car, 2: take bus, 3: take taxi, 4: bus route
  initialize-single-source source
  let Q vertices
  while [any? Q][
    let u min-one-of Q [weight]
    set Q Q with [self != u]
    let patch-u [patch-here] of u
    if ([land-type] of patch-u = "road" or u = source or u = target)[
      ask [link-neighbors] of u [
        let edge-btw edge [who] of u [who] of self
        ifelse (mode = 4)[       ;; bus route
          if ([bus-route?] of edge-btw = true)[
            relax u self edge-btw
          ]
        ][                       ;; people commuting
          ifelse ([bus-route?] of edge-btw = true)[
            if (mode = 2) [
              relax u self edge-btw
            ]
          ][
            relax u self edge-btw
          ]
        ]
      ]
    ]
  ]
end

to-report find-path [source target mode]
  dijkstra source target mode
  let path-list (list target)
  let pred [predecessor] of target
  while [pred != source][
    set path-list fput pred path-list  ;; fput: Add item to the beginning of a list
    set pred [predecessor] of pred
  ]
  report path-list
end
@#$#@#$#@
GRAPHICS-WINDOW
127
10
723
607
-1
-1
12.0
1
10
1
1
1
0
0
0
1
-24
24
-24
24
1
1
1
ticks
30.0

BUTTON
15
16
83
49
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
15
61
83
94
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
15
107
84
140
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
16
158
73
203
NIL
money
17
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

bus
true
0
Polygon -7500403 true true 206 285 150 285 120 285 105 270 105 30 120 15 135 15 206 15 210 30 210 270
Rectangle -16777216 true false 126 69 159 264
Line -7500403 true 135 240 165 240
Line -7500403 true 120 240 165 240
Line -7500403 true 120 210 165 210
Line -7500403 true 120 180 165 180
Line -7500403 true 120 150 165 150
Line -7500403 true 120 120 165 120
Line -7500403 true 120 90 165 90
Line -7500403 true 135 60 165 60
Rectangle -16777216 true false 174 15 182 285
Circle -16777216 true false 187 210 42
Rectangle -16777216 true false 127 24 205 60
Circle -16777216 true false 187 63 42
Line -7500403 true 120 43 207 43

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

car top
true
0
Polygon -7500403 true true 151 8 119 10 98 25 86 48 82 225 90 270 105 289 150 294 195 291 210 270 219 225 214 47 201 24 181 11
Polygon -16777216 true false 210 195 195 210 195 135 210 105
Polygon -16777216 true false 105 255 120 270 180 270 195 255 195 225 105 225
Polygon -16777216 true false 90 195 105 210 105 135 90 105
Polygon -1 true false 205 29 180 30 181 11
Line -7500403 false 210 165 195 165
Line -7500403 false 90 165 105 165
Polygon -16777216 true false 121 135 180 134 204 97 182 89 153 85 120 89 98 97
Line -16777216 false 210 90 195 30
Line -16777216 false 90 90 105 30
Polygon -1 true false 95 29 120 30 119 11

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person business
false
0
Rectangle -1 true false 120 90 180 180
Polygon -13345367 true false 135 90 150 105 135 180 150 195 165 180 150 105 165 90
Polygon -7500403 true true 120 90 105 90 60 195 90 210 116 154 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 183 153 210 210 240 195 195 90 180 90 150 165
Circle -7500403 true true 110 5 80
Rectangle -7500403 true true 127 76 172 91
Line -16777216 false 172 90 161 94
Line -16777216 false 128 90 139 94
Polygon -13345367 true false 195 225 195 300 270 270 270 195
Rectangle -13791810 true false 180 225 195 300
Polygon -14835848 true false 180 226 195 226 270 196 255 196
Polygon -13345367 true false 209 202 209 216 244 202 243 188
Line -16777216 false 180 90 150 165
Line -16777216 false 120 90 150 165

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

van top
true
0
Polygon -7500403 true true 90 117 71 134 228 133 210 117
Polygon -7500403 true true 150 8 118 10 96 17 85 30 84 264 89 282 105 293 149 294 192 293 209 282 215 265 214 31 201 17 179 10
Polygon -16777216 true false 94 129 105 120 195 120 204 128 180 150 120 150
Polygon -16777216 true false 90 270 105 255 105 150 90 135
Polygon -16777216 true false 101 279 120 286 180 286 198 281 195 270 105 270
Polygon -16777216 true false 210 270 195 255 195 150 210 135
Polygon -1 true false 201 16 201 26 179 20 179 10
Polygon -1 true false 99 16 99 26 121 20 121 10
Line -16777216 false 130 14 168 14
Line -16777216 false 130 18 168 18
Line -16777216 false 130 11 168 11
Line -16777216 false 185 29 194 112
Line -16777216 false 115 29 106 112
Line -7500403 false 210 180 195 180
Line -7500403 false 195 225 210 240
Line -7500403 false 105 225 90 240
Line -7500403 false 90 180 105 180

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

dotted
0.0
-0.2 0 0.0 1.0
0.0 1 4.0 4.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
