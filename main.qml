import QtQuick
import QtCore
import QtQuick.Controls
import QtQuick.Layouts
import Theme
import org.qfield
import org.qgis
import "qrc:/qml" as QFieldItems

Item {
    id: drivemeToolPlugin
    objectName: "driveMePlugin"
    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    
    // --- VARIABLES ---
    property var unvisitedPoints: []   
    property var currentTarget: null   
    property int totalPointsCount: 0
    property bool isNavigating: false
    property bool isPaused: false
    
    // HUD
    property string distanceText: "-- m"
    property string hudMessage: ""
    property bool hudMessagePersistent: false
    
    // ÉTATS
    property string navState: "DRIVING" 
    property var parkedLocation: null 

    // CONFIG
    property int chainWalkThreshold: 50 
    property var lastProcessPos: null
    property var lastRouteCoords: null
    property bool routeHasFootSegment: false
    property var lastFootPos: null
    property var polygonVertices: ({})
    property var polygonCenters: ({})
    property var traveledCoords: []
    property string _lastPolygonWkt: ""
    property string _lastOnRouteWkt: ""
    property string _lastCarRouteWkt: ""
    property string _lastFootRouteWkt: ""
    property string _lastArrowWkt: ""
    property bool _footFetchPending: false
    
    // Zoom & Filtres
    property real savedZoomHW: 0
    property real savedZoomHH: 0
    property var pendingDriveMeLayer: null
    property var pendingFeatExtent: null

    // --- RAYON DE MARCHE ---
    property real walkRadius: 200          
    property var lastFootRouteCoords: null 
    property bool targetJustValidated: false

    property string _editingKey: ""

    Settings {
    id: navColorSettings
    category: "DriveMeToolColors"
    property string carColor: "#FF00FF"
    property string footColor:  "#02AE0F"
    property string parkColor:   "#00FF00"
    property string targetColor: "##00FCF7"
    property string arrowColor:  "#FFFF00"
    property string footArrowColor: "#FFFF00"
    property string polygonColor: "cyan" 
}

    // --- COLOR WHEEL PICKER ---
    Popup {
        id: colorWheelPopup
        parent: mainWindow.contentItem
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        x: (parent.width  - width)  / 2
        y: (parent.height - height) / 2
        width: 280

        background: Rectangle {
            color: "white"; border.color: Theme.mainColor; border.width: 2; radius: 20
        }

        property real _hue: 0
        property real _sat: 0
        property real _val: 1

        function openFor(key) {
            drivemeToolPlugin._editingKey = key
            var hex = ""
            if (key === "car")       hex = navColorSettings.carColor
            if (key === "foot")      hex = navColorSettings.footColor
            if (key === "park")      hex = navColorSettings.parkColor
            if (key === "target")    hex = navColorSettings.targetColor
            if (key === "arrow")     hex = navColorSettings.arrowColor
            if (key === "footArrow") hex = navColorSettings.footArrowColor
            if (key === "polygon")   hex = navColorSettings.polygonColor
            _fromHex(hex)
            _updateAll()
            open()
        }

        function _applyColor() {
            var hex = _hsvToHex(_hue, _sat, _val)
            if (drivemeToolPlugin._editingKey === "car")       navColorSettings.carColor       = hex
            if (drivemeToolPlugin._editingKey === "foot")      navColorSettings.footColor      = hex
            if (drivemeToolPlugin._editingKey === "park")      navColorSettings.parkColor      = hex
            if (drivemeToolPlugin._editingKey === "target")    navColorSettings.targetColor    = hex
            if (drivemeToolPlugin._editingKey === "arrow")     navColorSettings.arrowColor     = hex
            if (drivemeToolPlugin._editingKey === "footArrow") navColorSettings.footArrowColor = hex
            if (drivemeToolPlugin._editingKey === "polygon")   navColorSettings.polygonColor   = hex
        }

        function _fromHex(hex) {
            if (!hex || hex.toString().length < 6) return
            var h = hex.toString()
            if (h.charAt(0) !== '#') h = '#' + h
            if (h.length === 9) h = '#' + h.slice(3)
            var r = parseInt(h.slice(1,3), 16) / 255
            var g = parseInt(h.slice(3,5), 16) / 255
            var b = parseInt(h.slice(5,7), 16) / 255
            var max = Math.max(r,g,b), min = Math.min(r,g,b), d = max - min
            _val = max; _sat = max === 0 ? 0 : d / max
            if (d === 0) _hue = 0
            else if (max === r) _hue = 60 * (((g-b)/d) % 6)
            else if (max === g) _hue = 60 * ((b-r)/d + 2)
            else _hue = 60 * ((r-g)/d + 4)
            if (_hue < 0) _hue += 360
            cwHexField.text = _hsvToHex(_hue, _sat, _val).toUpperCase()
        }

        function _hsvToHex(h, s, v) {
            var r, g, b
            var i = Math.floor(h/60) % 6
            var f = h/60 - Math.floor(h/60)
            var p=v*(1-s), q=v*(1-f*s), t=v*(1-(1-f)*s)
            if      (i===0){r=v;g=t;b=p} else if(i===1){r=q;g=v;b=p}
            else if (i===2){r=p;g=v;b=t} else if(i===3){r=p;g=q;b=v}
            else if (i===4){r=t;g=p;b=v} else{r=v;g=p;b=q}
            function toH(x) { return Math.round(x*255).toString(16).padStart(2,'0').toUpperCase() }
            return '#' + toH(r) + toH(g) + toH(b)
        }

        function _updateAll() {
            cwWheelCanvas.requestPaint()
            cwBrightCanvas.requestPaint()
            var hex = _hsvToHex(_hue, _sat, _val)
            cwHexField.text = hex
            cwPreview.color = hex
        }

        onOpened: _updateAll()

        ColumnLayout {
            id: cwMainCol
            width: 280
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 12
                spacing: 10

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    width: 240; height: 240

                    Canvas {
                        id: cwWheelCanvas
                        width: 240; height: 240
                        readonly property real cx:      120
                        readonly property real cy:      120
                        readonly property real outerR:  116
                        readonly property real innerR:  96
                        readonly property real ringMid: (outerR + innerR) / 2

                        function hsvToRgb(h, s, v) {
                            var r,g,b, i=Math.floor(h/60)%6, f=h/60-Math.floor(h/60)
                            var p=v*(1-s),q=v*(1-f*s),t=v*(1-(1-f)*s)
                            if(i===0){r=v;g=t;b=p}else if(i===1){r=q;g=v;b=p}
                            else if(i===2){r=p;g=v;b=t}else if(i===3){r=p;g=q;b=v}
                            else if(i===4){r=t;g=p;b=v}else{r=v;g=p;b=q}
                            return [Math.round(r*255),Math.round(g*255),Math.round(b*255)]
                        }

                        function triVerts() {
                            var h0 = colorWheelPopup._hue * Math.PI / 180
                            var h1 = h0 + 2*Math.PI/3
                            var h2 = h0 + 4*Math.PI/3
                            return [
                                { x: cx + innerR*Math.cos(h0), y: cy + innerR*Math.sin(h0) },
                                { x: cx + innerR*Math.cos(h1), y: cy + innerR*Math.sin(h1) },
                                { x: cx + innerR*Math.cos(h2), y: cy + innerR*Math.sin(h2) }
                            ]
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            for (var angle = 0; angle < 360; angle++) {
                                var sa = (angle - 0.5) * Math.PI / 180
                                var ea = (angle + 1.5) * Math.PI / 180
                                var rgb = hsvToRgb(angle, 1, 1)
                                ctx.beginPath()
                                ctx.moveTo(cx + innerR*Math.cos(sa), cy + innerR*Math.sin(sa))
                                ctx.arc(cx, cy, outerR, sa, ea)
                                ctx.arc(cx, cy, innerR, ea, sa, true)
                                ctx.closePath()
                                ctx.fillStyle = "rgb("+rgb[0]+","+rgb[1]+","+rgb[2]+")"
                                ctx.fill()
                            }
                            ctx.beginPath(); ctx.arc(cx,cy,outerR,0,Math.PI*2); ctx.strokeStyle="#777"; ctx.lineWidth=1; ctx.stroke()
                            ctx.beginPath(); ctx.arc(cx,cy,innerR,0,Math.PI*2); ctx.strokeStyle="#777"; ctx.lineWidth=1; ctx.stroke()

                            var vt = triVerts()
                            var t0=vt[0], t1=vt[1], t2=vt[2]
                            function triPath() {
                                ctx.beginPath()
                                ctx.moveTo(t0.x,t0.y); ctx.lineTo(t1.x,t1.y)
                                ctx.lineTo(t2.x,t2.y); ctx.closePath()
                            }
                            var rgb0 = hsvToRgb(colorWheelPopup._hue, 1, 1)
                            triPath(); ctx.fillStyle="rgb("+rgb0[0]+","+rgb0[1]+","+rgb0[2]+")"; ctx.fill()
                            var mid01x=(t0.x+t2.x)/2, mid01y=(t0.y+t2.y)/2
                            var gw = ctx.createLinearGradient(t1.x,t1.y, mid01x,mid01y)
                            gw.addColorStop(0,"rgba(255,255,255,1)"); gw.addColorStop(1,"rgba(255,255,255,0)")
                            triPath(); ctx.fillStyle=gw; ctx.fill()
                            var mid02x=(t0.x+t1.x)/2, mid02y=(t0.y+t1.y)/2
                            var gb = ctx.createLinearGradient(t2.x,t2.y, mid02x,mid02y)
                            gb.addColorStop(0,"rgba(0,0,0,1)"); gb.addColorStop(1,"rgba(0,0,0,0)")
                            triPath(); ctx.fillStyle=gb; ctx.fill()
                            triPath(); ctx.strokeStyle="rgba(0,0,0,0.25)"; ctx.lineWidth=1; ctx.stroke()
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed:         _handle(mouseX, mouseY)
                            onPositionChanged: if (pressed) _handle(mouseX, mouseY)
                            function _handle(mx, my) {
                                var dx=mx-cwWheelCanvas.cx, dy=my-cwWheelCanvas.cy
                                var dist=Math.sqrt(dx*dx+dy*dy)
                                if (dist >= cwWheelCanvas.innerR && dist <= cwWheelCanvas.outerR) {
                                    colorWheelPopup._hue = ((Math.atan2(dy,dx)*180/Math.PI)+360)%360
                                    colorWheelPopup._updateAll(); return
                                }
                                if (dist < cwWheelCanvas.innerR) {
                                    var vt = cwWheelCanvas.triVerts()
                                    var t0=vt[0], t1=vt[1], t2=vt[2]
                                    var denom = (t1.y-t2.y)*(t0.x-t2.x) + (t2.x-t1.x)*(t0.y-t2.y)
                                    if (Math.abs(denom) < 0.001) return
                                    var a = ((t1.y-t2.y)*(mx-t2.x) + (t2.x-t1.x)*(my-t2.y)) / denom
                                    var b = ((t2.y-t0.y)*(mx-t2.x) + (t0.x-t2.x)*(my-t2.y)) / denom
                                    var c = 1-a-b
                                    a=Math.max(0,a); b=Math.max(0,b); c=Math.max(0,c)
                                    var sum=a+b+c; a/=sum; b/=sum; c/=sum
                                    var newV = a+b
                                    colorWheelPopup._val = Math.max(0, Math.min(1, newV))
                                    colorWheelPopup._sat = Math.max(0, Math.min(1, newV > 0.001 ? a/newV : 0))
                                    colorWheelPopup._updateAll()
                                }
                            }
                        }
                    }

                    Rectangle {
                        property real rad: colorWheelPopup._hue * Math.PI / 180
                        x: cwWheelCanvas.cx + cwWheelCanvas.ringMid * Math.cos(rad) - 8
                        y: cwWheelCanvas.cy + cwWheelCanvas.ringMid * Math.sin(rad) - 8
                        width: 16; height: 16; radius: 8
                        color: "transparent"
                        border.color: "white"; border.width: 2.5
                        antialiasing: true
                    }

                    Rectangle {
                        property var verts: cwWheelCanvas.triVerts()
                        property var p0: verts[0]; property var p1: verts[1]; property var p2: verts[2]
                        property real sv: colorWheelPopup._sat
                        property real vv: colorWheelPopup._val
                        property real px: vv*(sv*p0.x + (1-sv)*p1.x) + (1-vv)*p2.x
                        property real py: vv*(sv*p0.y + (1-sv)*p1.y) + (1-vv)*p2.y
                        x: px - 8; y: py - 8
                        width: 16; height: 16; radius: 8
                        color: cwPreview.color
                        border.color: "white"; border.width: 2.5
                        antialiasing: true
                    }
                }

                Canvas { id: cwBrightCanvas; width:1; height:1; visible:false; onPaint:{} }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        id: cwPreview
                        width: 44; height: 44; radius: 22
                        color: "#FF0000"
                        border.color: "#aaa"; border.width: 2
                        antialiasing: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label { text: tr("Code couleur"); font.pixelSize: 10; color: "#888" }
                        TextField {
                            id: cwHexField
                            Layout.fillWidth: true
                            text: "#FF0000"
                            maximumLength: 7
                            font.pixelSize: 14
                            leftPadding: 8
                            background: Rectangle {
                                color: "#f5f5f5"
                                border.color: cwHexField.activeFocus ? Theme.mainColor : "#ccc"
                                border.width: 1; radius: 6
                            }
                            color: "#333"
                            onAccepted: {
                                var v = text.trim()
                                if (v.charAt(0) !== '#') v = '#' + v
                                if (v.length === 7) { colorWheelPopup._fromHex(v); colorWheelPopup._updateAll() }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Button {
                        text: tr("Annuler"); Layout.fillWidth: true
                        background: Rectangle { color: parent.down ? "#ddd" : "#eee"; radius: 15; border.color: "#ccc"; border.width: 1 }
                        contentItem: Text { text: parent.text; color: "#333"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: colorWheelPopup.close()
                    }
                    Button {
                        text: "OK"; Layout.fillWidth: true
                        background: Rectangle { color: parent.down ? Qt.darker(Theme.mainColor,1.2) : Theme.mainColor; radius: 15 }
                        contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: { colorWheelPopup._applyColor(); colorWheelPopup.close() }
                    }
                }

            }
        }
    }

    // --- TRADUCTION ---
    property string currentLang: "fr"
    function detectLanguage() {
        var loc = Qt.locale().name.substring(0, 2)
        currentLang = (loc === "fr") ? "fr" : "en"
    }

    property var translations: {
        "RESTANT": { "fr": "RESTANT", "en": "REMAINING" },
        "DISTANCE": { "fr": "DISTANCE", "en": "DISTANCE" },
        "NAVIGATION": { "fr": "NAVIGATION", "en": "NAVIGATION" },
        "Couche:": { "fr": "Couche :", "en": "Layer:" },
        "ARRÊTER": { "fr": "ARRÊTER", "en": "STOP" },
        "DÉMARRER": { "fr": "DÉMARRER", "en": "START" },
        "Aucun élément trouvé": { "fr": "Aucun élément trouvé", "en": "No features found" },
        "Aucun point trouvé": { "fr": "Aucun point trouvé", "en": "No points found" },
        "Calcul de l'itinéraire en pause": { "fr": "Calcul de l'itinéraire en pause", "en": "Calculate way in pause" },
        "Calcul de l'itinéraire activé": { "fr": "Calcul de l'itinéraire activé", "en": "Calculate way reactivated" },
        "✅ Cible atteinte !": { "fr": "✅ Cible atteinte !", "en": "✅ Target reached!" },
        "✅ Point validé\nau passage !": { "fr": "✅ Point validé\nau passage !", "en": "✅ Point validated\non the way!" },
        "Retour au véhicule.": { "fr": "Retour au véhicule.", "en": "Return to vehicle." },
        "🔄 Retour voiture :\naccès route plus court(-": { "fr": "🔄 Retour voiture :\naccès route plus court\n(-", "en": "🔄 Return to car:\nshorter road access(-" },
        "🏁 Terminé !": { "fr": "🏁 Terminé !", "en": "🏁 Done!" },
        "Accès à pied\n(point isolé)": { "fr": "Accès à pied\n(point isolé)", "en": "On foot\n(isolated point)" },
        "👟 À pied plus rapide": { "fr": "👟 À pied plus rapide", "en": "👟 Faster on foot" },
        "🚗 Retour voiture": { "fr": "🚗 Retour voiture", "en": "🚗 Back to car" },
        "min gagnées": { "fr": "min gagnées", "en": "min saved" },
        "En route.": { "fr": "En route.", "en": "Drive on." },
        "Fin de route.\nFinir à pied.": { "fr": "Fin de route.\nFinir à pied.", "en": "End of road.\nFinish on foot." },
        "Voiture stationnée.\nFinir à pied.": { "fr": "Voiture stationnée.\nFinir à pied.", "en": "Vehicle parked.\nFinish on foot." },
        "Vers les géométries de la couche :": { "fr": "Vers les géométries de la couche :", "en": "Towards the geometries of layer:" },
        "Sélectionnez une couche :": { "fr": "Sélectionnez une couche :", "en": "Select a layer:" },
        "Code couleur": { "fr": "Code couleur", "en": "Color code" },
        "Tracé voiture": { "fr": "Tracé voiture", "en": "Car road" },
        "Tracé piéton": { "fr": "Tracé piéton", "en": "Walk road" },
        "Flèches voiture": { "fr": "Flèches voiture", "en": "Road arrows" },
        "Flèches piéton": { "fr": "Flèches piéton", "en": "Walk arrows" },
        "Polygones": { "fr": "Géométrie cible", "en": "Target geometrie" },
        "Stationnement": { "fr": "Stationnement", "en": "Parking" },
        "Points cibles": { "fr": "Points cibles", "en": "Target points" },
        "Annuler": { "fr": "Annuler", "en": "Cancel" },
        "👟 ": { "fr": "👟 ", "en": "👟 " },
        " point(s) dans rayon 200m": { "fr": " point(s) dans rayon 200m", "en": " point(s) within 200m" },
        "👟 Prochain dans rayon\n(": { "fr": "👟 Prochain dans rayon\n(", "en": "👟 Next in radius\n(" },
        " restant(s))": { "fr": " restant(s))", "en": " remaining)" },
        "✅ Rayon terminé.\nRetour véhicule.": { "fr": "✅ Rayon terminé.\nRetour véhicule.", "en": "✅ Zone done.\nReturn to vehicle." },
        "🚗 Hors rayon 200m.\nRetour véhicule.": { "fr": "🚗 Hors rayon 200m.\nRetour véhicule.", "en": "🚗 Outside 200m.\nReturn to vehicle." },
        "🚗 Point route dans rayon.\nRetour véhicule.": { "fr": "🚗 Point route dans rayon.\nRetour véhicule.", "en": "🚗 Road point in radius.\nReturn to vehicle." }
    }

    function tr(key) {
        var t = translations[key]
        if (t) return t[currentLang] !== undefined ? t[currentLang] : key
        return key
    }

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(btnNav)
        detectLanguage()
    }

    // --- 1. RENDU ---

    QFieldItems.GeometryRenderer {
    id: arrowRenderer
    parent: mapCanvas
    mapSettings: mapCanvas.mapSettings
    geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
    lineWidth: 2
    color: navColorSettings.arrowColor
    opacity: 1.0
}

QFieldItems.GeometryRenderer {
    id: footArrowRendererPlugin
    parent: mapCanvas
    mapSettings: mapCanvas.mapSettings
    geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
    lineWidth: 2
    color: navColorSettings.footArrowColor
    opacity: 1.0
}

    QFieldItems.GeometryRenderer {
        id: onRouteRendererPlugin
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 14
        color: navColorSettings.targetColor
        opacity: 1.0
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: isNavigating
            NumberAnimation { from: 0.9; to: 0.1; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.1; to: 0.9; duration: 500; easing.type: Easing.InOutQuad }
        }
    }

    QFieldItems.GeometryRenderer {
        id: carRendererPlugin
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 6
        color: navColorSettings.carColor
        opacity: 1.0
    }

    QFieldItems.GeometryRenderer {
        id: footRendererPlugin
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 5
        color: navColorSettings.footColor
        opacity: 1.0
    }

    
    CoordinateTransformer {
        id: gpsMapTransformer
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
        transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
    }

    // --- 2. MARQUEURS ---
    CoordinateTransformer {
        id: targetTransformer
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
        transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
    }
    MapToScreen {
        id: targetScreenPosPlugin
        mapSettings: mapCanvas.mapSettings
        mapPoint: targetTransformer.projectedPosition
    }
    Item {
        id: blinkingTargetPlugin
        parent: mapCanvas
        visible: isNavigating && currentTarget !== null && navState !== "RETURNING_TO_CAR"
        x: targetScreenPosPlugin.screenPoint.x - width / 2
        y: targetScreenPosPlugin.screenPoint.y - height / 2
        width: 50; height: 50
        Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 8; color: navColorSettings.targetColor; border.color: "white"; border.width: 2 }
        Rectangle {
            anchors.centerIn: parent; width: parent.width; height: parent.height; radius: width / 2; color: "transparent"; border.color: navColorSettings.targetColor; border.width: 3
            SequentialAnimation on scale { loops: Animation.Infinite; running: blinkingTargetPlugin.visible; NumberAnimation { from: 0.2; to: 1.0; duration: 1200; easing.type: Easing.OutQuad } }
            SequentialAnimation on opacity { loops: Animation.Infinite; running: blinkingTargetPlugin.visible; NumberAnimation { from: 1.0; to: 0.0; duration: 1200; easing.type: Easing.OutQuad } }
        }
    }

    QFieldItems.GeometryRenderer {
        id: polygonCenterRendererPlugin
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 4
        color: navColorSettings.polygonColor
        opacity: 1.0
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: isNavigating
            NumberAnimation { 
from: 1.0
 to: 0.5
 duration: 500
 easing.type: Easing.InOutQuad }
            NumberAnimation { 
from: 0.5
 to: 1.0
 duration: 500
 easing.type: Easing.InOutQuad }
        }
    }

    CoordinateTransformer {
        id: carTransformerPlugin
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
        transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
    }
    MapToScreen {
        id: carScreenPosPlugin
        mapSettings: mapCanvas.mapSettings
        mapPoint: carTransformerPlugin.projectedPosition
    }
    Item {
        id: blinkingCarPlugin
        parent: mapCanvas
        visible: isNavigating && parkedLocation !== null
        x: carScreenPosPlugin.screenPoint.x - width / 2
        y: carScreenPosPlugin.screenPoint.y - height / 2
        width: 60; height: 60
        Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 10; color: navColorSettings.parkColor; border.color: "black"; border.width: 3 }
        Rectangle {
            anchors.centerIn: parent; width: parent.width; height: parent.height; radius: width / 2; color: "transparent"; border.color: navColorSettings.parkColor; border.width: 4
            SequentialAnimation on scale { loops: Animation.Infinite; running: blinkingCar.visible; NumberAnimation { from: 0.3; to: 1.0; duration: 1500; easing.type: Easing.OutQuad } }
            SequentialAnimation on opacity { loops: Animation.Infinite; running: blinkingCar.visible; NumberAnimation { from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutQuad } }
        }
    }

    // --- 3. HUD ---
    Rectangle {
        id: hudBarPlugin
        parent: mapCanvas 
        z: 9999
        visible: isNavigating
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: parent.width > parent.height ? 8 : 60
        width: Math.min(parent.width * 0.70, 360) 
        height: 48
        color: "#DD000000" 
        radius: 10
        border.color: "white"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 6

            Column {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignVCenter
                Text { text: tr("RESTANT"); color: "#FFFFFF"; font.pixelSize: 10; font.bold: true }
                Text { text: unvisitedPoints.length + " / " + totalPointsCount; color: "#00FF00"; font.pixelSize: 18; font.bold: true }
            }

            Rectangle { width: 1; height: 40; color: "gray"; Layout.alignment: Qt.AlignVCenter }

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignVCenter
                height: 40
                clip: true

                Text {
                    id: hudText
                    text: getHudText()
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on x {
                        id: marqueeAnim
                        loops: Animation.Infinite
                        running: hudText.implicitWidth > hudText.parent.width
                        PauseAnimation  { duration: 500 }
                        NumberAnimation {
                            from:     hudText.parent ? hudText.parent.width : 0
                            to:       -(hudText.implicitWidth)
                            duration: hudText.implicitWidth > 0
                                        ? (hudText.implicitWidth + (hudText.parent ? hudText.parent.width : 0)) * 16
                                        : 1
                            easing.type: Easing.Linear
                        }
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignVCenter
                Text { text: tr("DISTANCE"); color: "#FFFFFF"; font.pixelSize: 10; font.bold: true }
                Text { text: distanceText; color: "cyan"; font.pixelSize: 18; font.bold: true }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: parent.height
                QfToolButton {
                    anchors.centerIn: parent
                    iconSource: "icon.svg"
                    iconColor: isPaused ? "orange" : "red"
                    flat: true

                    onClicked: {
                        if (!isNavigating) return
                        isPaused = !isPaused
                        if (isPaused) showHudMessage("Navigation en pause")
                        else showHudMessage("Navigation reprise")
                    }

                    onPressAndHold: {
                        if (!isNavigating) return
                        isPaused = false
                        stopNavigation()
                        showHudMessage("Navigation arrêtée")
                    }
                }
            }
        }
    }

    Timer {
        id: hudMessageTimer
        interval: 5000
        repeat: false
        onTriggered: { if (!drivemeToolPlugin.hudMessagePersistent) hudMessage = "" }
    }

    Timer {
        id: resetPolygonTimer
        interval: 50
        repeat: false
        onTriggered: { updatePolygonCenterRenderer() }
    }

    function showHudMessage(text, persistent) {
        hudMessagePersistent = (persistent === true)   
        hudMessage = text
        if (!hudMessagePersistent) hudMessageTimer.restart()
        else hudMessageTimer.stop()
    }

    function getHudText() {
        if (hudMessage !== "") return hudMessage
        return ""
    }

    // --- 4. TIMER ---
    Timer {
        id: navTimer
        interval: 800
        repeat: true
        running: isNavigating && !isPaused
        onTriggered: updateNavigationLoop()
    }

    // --- ZOOM GPS + ENTITÉS FILTRÉES ---
    Timer {
        id: recenterTimer
        interval: 400
        repeat: false
        onTriggered: {
            try {
                let gpsPt = getCurrentGpsPosition()
                if (!gpsPt) gpsPt = getMapCenter()
                if (gpsPt) {
                    let gpsGeom = GeometryUtils.createGeometryFromWkt("POINT(" + gpsPt.x + " " + gpsPt.y + ")")
                    gpsMapTransformer.sourcePosition = GeometryUtils.centroid(gpsGeom)
                    let proj = gpsMapTransformer.projectedPosition
                    if (proj && (proj.x !== 0 || proj.y !== 0)) {
                        let featExt = pendingFeatExtent
                        if (featExt) {
                            let dx = Math.max(Math.abs(proj.x - featExt.xMinimum), Math.abs(proj.x - featExt.xMaximum))
                            let dy = Math.max(Math.abs(proj.y - featExt.yMinimum), Math.abs(proj.y - featExt.yMaximum))
                            dx = dx * 1.2; dy = dy * 1.2
                            let screenRatio = mapCanvas.width / (mapCanvas.height > 0 ? mapCanvas.height : 1)
                            if (dx / dy > screenRatio) dy = dx / screenRatio
                            else dx = dy * screenRatio
                            featExt.xMinimum = proj.x - dx; featExt.xMaximum = proj.x + dx
                            featExt.yMinimum = proj.y - dy; featExt.yMaximum = proj.y + dy
                            mapCanvas.mapSettings.setExtent(featExt, true)
                        }
                    }
                }
            } catch(e) { console.log("Erreur Zoom: " + e) }
            startDriveTimer.restart()
        }
    }

    Timer {
        id: startDriveTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (pendingDriveMeLayer !== null) {
                startNavigationProcess(pendingDriveMeLayer)
                pendingDriveMeLayer = null
                zoomToGpsTimer.restart()
            }
        }
    }

    Timer {
        id: zoomToGpsTimer
        interval: 2000
        repeat: false
        onTriggered: {
            try {
                let gpsPt = getCurrentGpsPosition()
                if (gpsPt) {
                    let gpsGeom = GeometryUtils.createGeometryFromWkt("POINT(" + gpsPt.x + " " + gpsPt.y + ")")
                    if (gpsGeom) {
                        gpsMapTransformer.sourcePosition = GeometryUtils.centroid(gpsGeom)
                        let proj = gpsMapTransformer.projectedPosition
                        if (proj && (proj.x !== 0 || proj.y !== 0)) {
                            let ext = mapCanvas.mapSettings.extent
                            let destCrs = mapCanvas.mapSettings.destinationCrs
                            let zoomRadius = 200
                            if (destCrs && destCrs.isGeographic) zoomRadius = 0.0018
                            let screenRatio = mapCanvas.width / (mapCanvas.height > 0 ? mapCanvas.height : 1)
                            let hw = zoomRadius, hh = zoomRadius / screenRatio
                            ext.xMinimum = proj.x - hw; ext.xMaximum = proj.x + hw
                            ext.yMinimum = proj.y - hh; ext.yMaximum = proj.y + hh
                            mapCanvas.mapSettings.setExtent(ext, true)
                        }
                    }
                }
            } catch(e) {}
        }
    }

    // --- 5. POINT D'ENTRÉE EXTERNE ---
    function startWithLayer(layer) {
        if (layer) startNavigationProcess(layer)
    }

    function startWithLayerAndExtent(layer, featExtent) {
        if (!layer) return
        pendingDriveMeLayer = layer
        pendingFeatExtent = featExtent
        recenterTimer.restart()
    }

    // --- 5b. BOUTON TOOLBAR ---
    QfToolButton {
        id: btnNav
        iconSource: "icon.svg"
        iconColor: { if (isPaused) return "orange"; if (isNavigating) return "red"; "#89cc28" } 
        bgcolor: Theme.darkGray
        round: true
        onClicked: { updateLayers(); dialogNav.open() }
        onPressAndHold: {
            if (!isNavigating) return
            isPaused = false
            stopNavigation()
            showHudMessage("Navigation arrêtée")
        }
    }

    // --- 5c. DIALOGUE DE NAVIGATION ---
    Dialog {
        id: dialogNav
        parent: mainWindow.contentItem
        modal: true
        width: Math.min(mainWindow.width * 0.8, 450)
        x: (mainWindow.width - width) / 2
        y: (mainWindow.height - height) / 2
        background: Rectangle { color: "white"; border.color: Theme.mainColor; border.width: 2; radius: 20 }

        property bool isLandscape: mainWindow.width > mainWindow.height
        property real scaleFactor: isLandscape ? Math.min(1.0, mainWindow.height * 0.92 / Math.max(implicitHeight, 1)) : 1.0
        scale: scaleFactor

        contentItem: ColumnLayout {
            spacing: 0
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: titleLabel.implicitHeight + 5
                color: "white"
                radius: 8
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.radius; color: parent.color }
                Label {
                    id: titleLabel
                    anchors.centerIn: parent
                    text: tr("NAVIGATION")
                    font.bold: true; font.pixelSize: 18; color: Theme.mainColor
                }
            }

            ColumnLayout {
                spacing: 15
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 6

                Label { text: tr("Vers les géométries de la couche :") }
                QfComboBox { id: layerSelector; Layout.fillWidth: true; model: []; enabled: !isNavigating; displayText: currentIndex === -1 ? tr("Sélectionnez une couche") : currentText }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2; columnSpacing: 8; rowSpacing: 8

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("car") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 4; color: navColorSettings.carColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Tracé voiture"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("foot") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 4; color: navColorSettings.footColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Tracé piéton"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("arrow") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 4; color: navColorSettings.arrowColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Flèches voiture"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("footArrow") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 4; color: navColorSettings.footArrowColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Flèches piéton"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("park") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 10; color: navColorSettings.parkColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Stationnement"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("target") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 10; color: navColorSettings.targetColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Points cibles"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#259E9E9E"; border.color: Theme.controlBorderColor; border.width: 1; radius: 6
                        MouseArea { anchors.fill: parent; onClicked: colorWheelPopup.openFor("polygon") }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 6
                            Rectangle { width: 20; height: 20; radius: 4; color: navColorSettings.polygonColor; border.color: "gray"; border.width: 1 }
                            Label { text: tr("Polygones"); font.pixelSize: 12; font.bold: true; color: Theme.mainTextColor; Layout.fillWidth: true }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Button {
                        text: tr("ARRÊTER")
 visible: isNavigating; Layout.fillWidth: true
                        background: Rectangle { color: "#dc3545"; radius: 15 }
                        contentItem: Text { 
text: parent.text
 color: "white"
 font.bold: true
 horizontalAlignment: Text.AlignHCenter
 verticalAlignment: Text.AlignVCenter }
                        onClicked: { 
stopNavigation()
 dialogNav.close() }
                    }
                    Button {
    text: tr("DÉMARRER")
    visible: !isNavigating
    Layout.fillWidth: true
    background: Rectangle { 
        color: Theme.mainColor 
        radius: 15 
    }
    contentItem: Text { 
        text: parent.text
        color: "white"
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter 
    }
    onClicked: {
        if (layerSelector.currentText) {
            var l = getLayerByName(layerSelector.currentText) // Utilise 'var' au lieu de 'let' pour plus de compatibilité QField
            if (l) {
                pendingDriveMeLayer = l
                var selectedFeats = l.selectedFeatures()
                
                if (selectedFeats && selectedFeats.length > 0) {
                    pendingFeatExtent = l.boundingBoxOfSelected()
                } else {
                    pendingFeatExtent = l.extent
                }
                
                recenterTimer.restart()
                dialogNav.close()
            }
        }
    }
}
                }
            }
        }
    }

    // --- 5d. FONCTIONS DIALOGUE ---
    function updateLayers() {
        let layers = ProjectUtils.mapLayers(qgisProject)
        let list = []
        for (let id in layers) {
            let l = layers[id]
            if (l && l.type === 0) list.push(l.name)
        }
        list.sort()
        layerSelector.model = list
        layerSelector.currentIndex = -1 
    }

    function getLayerByName(name) {
        let layers = ProjectUtils.mapLayers(qgisProject)
        for (let id in layers) { if (layers[id].name === name) return layers[id] }
        return null
    }

    // --- 6. NAVIGATION ---
    function stopNavigation() {
        isNavigating = false; isPaused = false; hudMessagePersistent = false; hudMessage = ""
        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)")
        if(empty) {
    carRendererPlugin.geometryWrapper.qgsGeometry = empty; footRendererPlugin.geometryWrapper.qgsGeometry = empty
    onRouteRendererPlugin.geometryWrapper.qgsGeometry = empty; polygonCenterRendererPlugin.geometryWrapper.qgsGeometry = empty
    arrowRenderer.geometryWrapper.qgsGeometry = empty; footArrowRendererPlugin.geometryWrapper.qgsGeometry = empty
}
        let emptyPoint = GeometryUtils.createGeometryFromWkt("POINT(0 0)")
        if (emptyPoint) carTransformerPlugin.sourcePosition = GeometryUtils.centroid(emptyPoint)
        lastRouteCoords = null; routeHasFootSegment = false; lastFootPos = null; lastFootRouteCoords = null
        polygonVertices = {}; polygonCenters = {}; traveledCoords = []
        mapCanvas.refresh()
        _lastOnRouteWkt = ""
        _lastCarRouteWkt = ""
        _lastFootRouteWkt = ""
        _lastArrowWkt = ""
        _lastPolygonWkt = ""
        _footFetchPending = false
        lastFootPos = null
    }

    function startNavigationProcess(layer) {
        try {
            chainWalkThreshold = 50
            let preSelected = layer.selectedFeatures()
            let hasPreSelection = preSelected && preSelected.length > 0
            let feats = []
            if (hasPreSelection) feats = preSelected
            else { layer.selectAll(); feats = layer.selectedFeatures(); layer.removeSelection() }
            if (!feats || feats.length === 0) { showHudMessage(tr("Aucun élément trouvé")); return }
            if (hasPreSelection) layer.removeSelection()
            let startPos = getCurrentGpsPosition()
            if (!startPos) startPos = getMapCenter()
            let rawPoints = resolvePolygonBoundaryPoints(feats, layer, startPos)
            if (rawPoints.length < 1) { showHudMessage(tr("Aucun point trouvé")); return }
            proceedWithNavigation(rawPoints)
        } catch(e) {}
    }

    function resolvePolygonBoundaryPoints(feats, layer, refPos) {
        let rawPoints = []
        let hasRoute = lastRouteCoords && lastRouteCoords.length >= 2
        let hasParking = parkedLocation && parkedLocation.x

        for (let i = 0; i < feats.length; i++) {
            let g = feats[i].geometry
            if (!g) continue
            let centPt = GeometryUtils.centroid(g)
            if (!centPt) continue
            let wgsFallback = GeometryUtils.reprojectPointToWgs84(centPt, layer.crs)
            if (!wgsFallback) continue
            let fallback = { id: i, x: wgsFallback.x, y: wgsFallback.y, onRoute: false }

            try {
                let innerPt = GeometryUtils.pointOnSurface ? GeometryUtils.pointOnSurface(g) : null
                let innerWgs = innerPt ? GeometryUtils.reprojectPointToWgs84(innerPt, layer.crs) : null
                polygonCenters[i] = innerWgs ? { x: innerWgs.x, y: innerWgs.y } : { x: wgsFallback.x, y: wgsFallback.y }
            } catch(e) { polygonCenters[i] = { x: wgsFallback.x, y: wgsFallback.y } }

            try {
                let wkt = g.asWkt()
                let coords = parseOuterRingCoords(wkt)
                if (!coords || coords.length < 2) { rawPoints.push(fallback); continue }
                let vertices = []
                for (let j = 0; j < coords.length; j++) {
                    let vWkt = "POINT(" + coords[j][0] + " " + coords[j][1] + ")"
                    let vGeom = GeometryUtils.createGeometryFromWkt(vWkt)
                    if (!vGeom) continue
                    let vPt = GeometryUtils.centroid(vGeom)
                    if (!vPt) continue
                    let vWgs = GeometryUtils.reprojectPointToWgs84(vPt, layer.crs)
                    if (!vWgs) continue
                    vertices.push({ x: vWgs.x, y: vWgs.y })
                }
                if (vertices.length === 0) { rawPoints.push(fallback); continue }
                let sampledVerts = sampleBoundaryWithEdgePoints(vertices, 15)
                polygonVertices[i] = sampledVerts

                let bestPt = null; let bestDist = 1e9
                if (hasParking) {
                    for (let k = 0; k < sampledVerts.length; k++) {
                        let dParking = getDistMeters(parkedLocation, sampledVerts[k])
                        let dRoute = hasRoute ? minDistToRouteLine(sampledVerts[k], lastRouteCoords) : 0
                        let d = dParking + dRoute
                        if (d < bestDist) { bestDist = d; bestPt = sampledVerts[k] }
                    }
                } else if (hasRoute) {
                    for (let k = 0; k < sampledVerts.length; k++) {
                        let d = minDistToRouteLine(sampledVerts[k], lastRouteCoords)
                        if (d < bestDist) { bestDist = d; bestPt = sampledVerts[k] }
                    }
                    if (bestDist > 200) {
                        bestDist = 1e9; bestPt = null
                        for (let k = 0; k < sampledVerts.length; k++) {
                            let d = getDistMeters(refPos || fallback, sampledVerts[k])
                            if (d < bestDist) { bestDist = d; bestPt = sampledVerts[k] }
                        }
                    }
                } else {
                    for (let k = 0; k < sampledVerts.length; k++) {
                        let d = getDistMeters(refPos || fallback, sampledVerts[k])
                        if (d < bestDist) { bestDist = d; bestPt = sampledVerts[k] }
                    }
                }
                if (!bestPt) { rawPoints.push(fallback); continue }
                let isOnRoute = hasRoute ? (minDistToRouteLine(bestPt, lastRouteCoords) < 20) : false
                let isIsolated = hasRoute && bestDist > 200
                rawPoints.push({ id: i, x: bestPt.x, y: bestPt.y, onRoute: isOnRoute, isolated: isIsolated })
            } catch(e) { rawPoints.push(fallback) }
        }
        chainIsolatedPoints(rawPoints)
        return rawPoints
    }

    function minDistToRouteLine(pt, routeCoords) {
        let coords = routeCoords || lastRouteCoords
        if (!coords || coords.length < 2) return 1e9
        let minD = 1e9
        for (let i = 0; i < coords.length - 1; i++) {
            let a = { x: coords[i][0], y: coords[i][1] }, b = { x: coords[i+1][0], y: coords[i+1][1] }
            let d = distPointToSegmentMeters(pt, a, b)
            if (d < minD) minD = d
        }
        let last = { x: coords[coords.length-1][0], y: coords[coords.length-1][1] }
        let dLast = getDistMeters(pt, last)
        if (dLast < minD) minD = dLast
        return minD
    }

    function distPointToSegmentMeters(pt, a, b) {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if (lenSq < 1e-12) return getDistMeters(pt, a)
        let t = ((pt.x - a.x) * dx + (pt.y - a.y) * dy) / lenSq
        t = Math.max(0, Math.min(1, t))
        let proj = { x: a.x + t * dx, y: a.y + t * dy }
        return getDistMeters(pt, proj)
    }

    function updateOnRouteRenderer() {
    let onRoutePts = unvisitedPoints.filter(function(p) { return p.onRoute })
    if (onRoutePts.length === 0) { clearGeometry(onRouteRendererPlugin); _lastOnRouteWkt = ""; return }
    let pts = []
    for (let i = 0; i < onRoutePts.length; i++) pts.push(onRoutePts[i].x.toFixed(6) + " " + onRoutePts[i].y.toFixed(6))
    let wkt = "MULTIPOINT(" + pts.join(",") + ")"
    if (wkt === _lastOnRouteWkt) return
    _lastOnRouteWkt = wkt
    let geom = GeometryUtils.createGeometryFromWkt(wkt)
    if (geom) onRouteRendererPlugin.geometryWrapper.qgsGeometry = geom
}

    function parseOuterRingCoords(wkt) {
        try {
            let cleaned = wkt.replace(/^MULTIPOLYGON\s*\(\s*\(\s*\(/, "((").replace(/^POLYGON\s*\(/, "(")
            let match = cleaned.match(/\(([^)]+)\)/)
            if (!match) return null
            let pairs = match[1].trim().split(",")
            let coords = []
            for (let i = 0; i < pairs.length; i++) {
                let parts = pairs[i].trim().split(/\s+/)
                if (parts.length >= 2) {
                    let x = parseFloat(parts[0]), y = parseFloat(parts[1])
                    if (!isNaN(x) && !isNaN(y)) coords.push([x, y])
                }
            }
            return coords.length >= 2 ? coords : null
        } catch(e) { return null }
    }

    function sampleBoundaryWithEdgePoints(vertices, samplingDistMeters) {
        if (!vertices || vertices.length < 2) return vertices
        let step = samplingDistMeters || 15; let result = []
        for (let i = 0; i < vertices.length; i++) {
            result.push(vertices[i])
            let j = i + 1; if (j >= vertices.length) break
            let d = getDistMeters(vertices[i], vertices[j])
            if (d > step) {
                let nSamples = Math.floor(d / step)
                for (let k = 1; k < nSamples; k++) {
                    let t = k / nSamples
                    result.push({ x: vertices[i].x + t * (vertices[j].x - vertices[i].x), y: vertices[i].y + t * (vertices[j].y - vertices[i].y) })
                }
            }
        }
        if (result.length > 80) {
            let stride = Math.ceil(result.length / 80); let reduced = []
            for (let i = 0; i < result.length; i += stride) reduced.push(result[i])
            return reduced
        }
        return result
    }

    function findBestWalkingBoundaryPoint(target, callback) {
        let verts = polygonVertices[target.id]
        if (!verts || verts.length === 0) { callback(target); return }
        let locations = verts.map(function(v) { return { lon: v.x, lat: v.y } })
        let body = JSON.stringify({ locations: locations, costing: "pedestrian" })
        var req = new XMLHttpRequest()
        req.timeout = 5000; req.ontimeout = function() { callback(target) }; req.onerror = req.ontimeout
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText); let bestDist = 1e9; let bestVert = null; let bestWalkX = null, bestWalkY = null
                    for (let k = 0; k < json.length && k < verts.length; k++) {
                        let entry = json[k]
                        if (entry && entry.edges && entry.edges.length > 0) {
                            let edge = entry.edges[0]
                            if (edge.correlated_lat !== undefined && edge.correlated_lon !== undefined) {
                                let snapDist = getDistMeters(verts[k], { x: edge.correlated_lon, y: edge.correlated_lat })
let distToRef = refPos ? getDistMeters(verts[k], refPos) : 0
let d = snapDist + distToRef * 0.4
if (d < bestDist) { bestDist = d; bestVert = verts[k]; bestWalkX = edge.correlated_lon; bestWalkY = edge.correlated_lat }
                            //    let d = getDistMeters(verts[k], { x: edge.correlated_lon, y: edge.correlated_lat })
                                if (d < bestDist) { bestDist = d; bestVert = verts[k]; bestWalkX = edge.correlated_lon; bestWalkY = edge.correlated_lat }
                            }
                        }
                    }
                    if (bestVert) {
                        callback({ id: target.id, x: bestVert.x, y: bestVert.y, walkX: bestWalkX, walkY: bestWalkY, onRoute: false, isolated: target.isolated })
                        return
                    }
                } catch(e) {}
            }
            callback(target)
        }
        req.open("POST", "https://valhalla1.openstreetmap.de/locate"); req.setRequestHeader("Content-Type", "application/json"); req.send(body)
    }

    function isPositionInsidePolygon(pos, ptId) {
        let verts = polygonVertices[ptId]; if (!verts || verts.length < 3) return false
        let x = pos.x, y = pos.y; let inside = false; let n = verts.length
        for (let i = 0, j = n - 1; i < n; j = i++) {
            let xi = verts[i].x, yi = verts[i].y; let xj = verts[j].x, yj = verts[j].y
            if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) inside = !inside
        }
        return inside
    }

    function proceedWithNavigation(rawPoints) {
        if (rawPoints.length < 1) { showHudMessage(tr("Aucun point trouvé")); return }
        unvisitedPoints = rawPoints; totalPointsCount = rawPoints.length
        let startPos = getCurrentGpsPosition()
        if (!startPos) startPos = getMapCenter()
        if (!startPos) startPos = rawPoints[0]
        currentTarget = getClosestPoint(startPos, unvisitedPoints).point
        navState = "DRIVING"; parkedLocation = null; isNavigating = true
        lastProcessPos = null; lastFootRouteCoords = null
        if (unvisitedPoints.length >= 2 && unvisitedPoints.length < 50) optimizeEntireTour(startPos)
        updateNavigationLoop()
    }

    function optimizeEntireTour(startPos) {
        let coords = startPos.x.toFixed(6) + "," + startPos.y.toFixed(6) + ";"
        coords += unvisitedPoints.map(p => p.x.toFixed(6) + "," + p.y.toFixed(6)).join(";")
        let url = "https://routing.openstreetmap.de/routed-car/trip/v1/driving/" + coords + "?source=first"
        var xhrTrip = new XMLHttpRequest()
        xhrTrip.onreadystatechange = function() {
            if (xhrTrip.readyState === XMLHttpRequest.DONE && xhrTrip.status === 200) {
                try {
                    let json = JSON.parse(xhrTrip.responseText)
                    if (json.waypoints) {
                        let newOrder = []
                        let waypoints = json.waypoints.sort((a,b) => a.waypoint_index - b.waypoint_index)
                        for (let i = 0; i < waypoints.length; i++) {
                            let idx = waypoints[i].location_index
                            if (idx > 0) newOrder.push(unvisitedPoints[idx - 1])
                        }
                        if (newOrder.length === unvisitedPoints.length) { unvisitedPoints = newOrder; currentTarget = unvisitedPoints[0] }
                    }
                } catch(e) {}
            }
        }
        xhrTrip.open("GET", url); xhrTrip.send()
    }

    function getClosestPoint(pos, pointsArray) {
        if (!pointsArray || pointsArray.length === 0) return null
        let minDist = 1e9; let closest = null
        for (let i = 0; i < pointsArray.length; i++) {
            let d = getDistMeters(pos, pointsArray[i])
            if (d < minDist) { minDist = d; closest = pointsArray[i] }
        }
        return { point: closest, distance: minDist }
    }

    // --- 8. BOUCLE PRINCIPALE ---
    function updateNavigationLoop() {
        if (!isNavigating || isPaused) return
        let myPos = getCurrentGpsPosition()
        if (!myPos) myPos = getCrosshairPosition()
        if (!myPos) return

//-------WITHOUT CALCULATION FROM CROSSHAIR-------
        let crosshairPos = getCrosshairPosition()
        let crosshairOnGps = !crosshairPos || getDistMeters(myPos, crosshairPos) <= 20
        let routePos = myPos  // itinéraire toujours calculé depuis la position GPS réelle
//-------WITH CALCULATION FROM CROSSHAIR----------
       // let crosshairPos = getCrosshairPosition()
       // let routePos = (crosshairPos && getDistMeters(myPos, crosshairPos) > 20) ? crosshairPos : myPos
//==============================================

        if (navState === "DRIVING") {
            let lastTraveled = traveledCoords.length > 0 ? traveledCoords[traveledCoords.length - 1] : null
            if (!lastTraveled || getDistMeters(myPos, lastTraveled) > 15) traveledCoords.push({ x: myPos.x, y: myPos.y })
        }

        let targetDist = 0
        if (navState === "RETURNING_TO_CAR" && parkedLocation) targetDist = getDistMeters(routePos, parkedLocation)
        else if (currentTarget) targetDist = getDistMeters(routePos, currentTarget)
        
        if (targetDist > 1000) distanceText = (targetDist / 1000).toFixed(1) + " km"
        else if (targetDist > 0) distanceText = Math.round(targetDist) + " m"
        else distanceText = "-- m"

        let targetWasValidated = false
        let remainingPoints = []
        let flybyRadius = (navState === "DRIVING" || navState === "RETURNING_TO_CAR") ? 15 : 10

        for (let i = 0; i < unvisitedPoints.length; i++) {
            let pt = unvisitedPoints[i]
            let nearNow = getDistMeters(myPos, pt) <= flybyRadius || (crosshairPos && getDistMeters(crosshairPos, pt) <= flybyRadius)
            if (!nearNow) {
                let verts = polygonVertices[pt.id]
                if (verts && verts.length > 0) {
                    for (let v = 0; v < verts.length; v++) {
                        if (getDistMeters(myPos, verts[v]) <= flybyRadius || (crosshairPos && getDistMeters(crosshairPos, verts[v]) <= flybyRadius)) {
                            nearNow = true; break
                        }
                    }
                }
            }
            if (!nearNow && polygonVertices[pt.id] && polygonVertices[pt.id].length >= 3) {
                nearNow = isPositionInsidePolygon(myPos, pt.id)
                if (!nearNow && crosshairPos) nearNow = isPositionInsidePolygon(crosshairPos, pt.id)
            }
            let nearTraveled = false
            if (!nearNow && pt.onRoute) {
                for (let t = 0; t < traveledCoords.length; t++) {
                    if (getDistMeters(traveledCoords[t], pt) <= flybyRadius) { nearTraveled = true; break }
                    let verts2 = polygonVertices[pt.id]
                    if (verts2 && verts2.length > 0) {
                        for (let v = 0; v < verts2.length; v++) {
                            if (getDistMeters(traveledCoords[t], verts2[v]) <= flybyRadius) { nearTraveled = true; break }
                        }
                    }
                    if (nearTraveled) break
                }
            }
            if (nearNow || nearTraveled) {
                if (currentTarget && pt.id === currentTarget.id) {
                    targetWasValidated = true
                    showHudMessage(tr("✅ Cible atteinte !"), true)
                } else {
                    showHudMessage(tr("✅ Point validé\nau passage !"), true)
                }
            } else { remainingPoints.push(pt) }
        }
        unvisitedPoints = remainingPoints
        if (targetWasValidated) targetJustValidated = true
        updateOnRouteRenderer(); updatePolygonCenterRenderer(); updateArrowRenderer()

        if (unvisitedPoints.length === 0) {
            if (parkedLocation && navState !== "RETURNING_TO_CAR") {
                navState = "RETURNING_TO_CAR"; showHudMessage(tr("Retour au véhicule."))
            } else if (navState !== "RETURNING_TO_CAR") {
                stopNavigation(); showHudMessage(tr("🏁 Terminé !"), true); return
            }
        } 
        else if (targetWasValidated || !currentTarget || !unvisitedPoints.find(p => p.id === currentTarget.id)) {
            if (parkedLocation) {
                let isolatedInRadius = getPointsInWalkRadius(parkedLocation, unvisitedPoints).filter(function(p) { return p.isolated }).sort(function(a, b) { return getDistMeters(routePos, a) - getDistMeters(routePos, b) })
                if (isolatedInRadius.length > 0) {
                    currentTarget = isolatedInRadius[0]; lastFootRouteCoords = null; navState = "WALKING_TO_POI"; lastFootPos = null; targetJustValidated = false
                    updatePolygonCenterRenderer(); updateArrowRenderer()
                    showHudMessage(tr("👟 ") + isolatedInRadius.length + tr(" point(s) dans rayon 200m"), true)
                } else {
                    let walkSpeed = 1.2, driveSpeed = 8.3, distToParked = getDistMeters(routePos, parkedLocation)
                    let bestWalkTarget = null, bestWalkScore = 1e9
                    for (let w = 0; w < unvisitedPoints.length; w++) {
                        let candidate = unvisitedPoints[w], distToCandidate = getDistMeters(routePos, candidate)
                        if (distToCandidate > walkRadius) continue
                        let timeWalk = distToCandidate / walkSpeed, driveDistEst = getDistMeters(parkedLocation, candidate) * 1.4, timeCar = distToParked / walkSpeed + driveDistEst / driveSpeed
                        if (timeWalk < timeCar && distToCandidate < bestWalkScore) { bestWalkScore = distToCandidate; bestWalkTarget = candidate }
                    }
                    if (bestWalkTarget) {
                        currentTarget = bestWalkTarget; targetJustValidated = false; lastFootRouteCoords = null; navState = "WALKING_TO_POI"
                        updatePolygonCenterRenderer(); updateArrowRenderer()
                        showHudMessage(tr("👟 Plus rapide à pied\n(") + Math.round(getDistMeters(routePos, bestWalkTarget)) + "m)", true)
                    } else {
                        lastFootRouteCoords = null; navState = "RETURNING_TO_CAR"; showHudMessage(tr("✅ Rayon terminé.\nRetour véhicule."), true)
                    }
                }
            } else {
                lastRouteCoords = null; currentTarget = null; navState = "DRIVING"; lastProcessPos = null
                selectNextTarget(routePos, function(bestTarget) {
                    if (navState !== "DRIVING" || !bestTarget || !unvisitedPoints.find(p => p.id === bestTarget.id)) return
                    currentTarget = bestTarget; targetJustValidated = false; updateOnRouteRenderer(); updatePolygonCenterRenderer(); updateArrowRenderer() //; mapCanvas.refresh()
                })
            }
        }

        if (unvisitedPoints.length === 0 && navState !== "RETURNING_TO_CAR") return

        let activeTarget = (navState === "RETURNING_TO_CAR" && parkedLocation) ? parkedLocation : currentTarget
        if (activeTarget && activeTarget.x) {
            let wktTarget = "POINT(" + activeTarget.x + " " + activeTarget.y + ")"
            let g = GeometryUtils.createGeometryFromWkt(wktTarget)
            if(g) targetTransformer.sourcePosition = GeometryUtils.centroid(g)
        }
        if (parkedLocation && parkedLocation.x) {
            let wktCar = "POINT(" + parkedLocation.x + " " + parkedLocation.y + ")"
            let g = GeometryUtils.createGeometryFromWkt(wktCar)
            if(g) carTransformerPlugin.sourcePosition = GeometryUtils.centroid(g)
        } else {
            let emptyPoint = GeometryUtils.createGeometryFromWkt("POINT(0 0)")
            if(emptyPoint) carTransformerPlugin.sourcePosition = GeometryUtils.centroid(emptyPoint)
        }

        var needsRefresh = false
        if (navState === "RETURNING_TO_CAR") {
            if (!parkedLocation) return
            if (getDistMeters(routePos, parkedLocation) < 20) {
                parkedLocation = null; navState = "DRIVING"; lastProcessPos = null; lastRouteCoords = null; lastFootPos = null; lastFootRouteCoords = null
                showHudMessage(tr("En route.")); updateNavigationLoop(); return
            }
            clearGeometry(carRendererPlugin)
            if (!lastFootRouteCoords) { lastFootPos = routePos; fetchFootRoute(routePos, parkedLocation); needsRefresh = true }
            else {
                if (getDistMeters(routePos, { x: lastFootRouteCoords[0][0], y: lastFootRouteCoords[0][1] }) > 50) { lastFootRouteCoords = null; lastFootPos = routePos; fetchFootRoute(routePos, parkedLocation) }
                else trimFootRouteToCurrentPos(routePos)
                needsRefresh = true
            }
        } 
        else if (navState === "WALKING_TO_POI") {
            if (!currentTarget) return
            if (parkedLocation) {
                if (getDistMeters(parkedLocation, currentTarget) > walkRadius) {
                    lastFootRouteCoords = null; navState = "RETURNING_TO_CAR"; showHudMessage(tr("🚗 Hors rayon 200m.\nRetour véhicule."), true); return
                }
                if (!currentTarget.isolated && currentTarget.onRoute) {
                    lastFootRouteCoords = null; navState = "RETURNING_TO_CAR"; showHudMessage(tr("🚗 Point route dans rayon.\nRetour véhicule."), true); return
                }
            }
            clearGeometry(carRendererPlugin)
            if (!lastFootRouteCoords) {
            if (!_footFetchPending) {
            let footStart = (!lastFootPos && parkedLocation) ? parkedLocation : routePos
            lastFootPos = footStart
            _footFetchPending = true
            fetchFootRoute(footStart, currentTarget)
            }
            needsRefresh = true
            }
       else {
           if (getDistMeters(routePos, { x: lastFootRouteCoords[0][0], y: lastFootRouteCoords[0][1] }) > 50) {
           lastFootRouteCoords = null
           lastFootPos = routePos
           }
           else trimFootRouteToCurrentPos(routePos)
           needsRefresh = true
         }
        }
        else if (navState === "DRIVING") {
            if (!currentTarget) return
            if (lastRouteCoords && lastRouteCoords.length >= 2) { if (trimRouteToCurrentPos(routePos)) needsRefresh = true }

//=======WITH WAY CALCULATION FROM CROSSHAIR=====
         //   if (!lastProcessPos || getDistMeters(routePos, lastProcessPos) > 40) { lastProcessPos = routePos; fetchOsrmRoute(routePos, currentTarget) }
//==========================================

//=====WITHOUT WAY CALCULATION FROM CROSSHAIR====
           if (crosshairOnGps && (!lastProcessPos || getDistMeters(routePos, lastProcessPos) > 40)) {
           lastProcessPos = routePos
           fetchOsrmRoute(routePos, currentTarget)
}
//===========================================

        }
     //   if (needsRefresh) mapCanvas.refresh()
    }

    function selectNextTarget(pos, onDone) {
        let snapNavState = navState; let allVerts = []
        for (let i = 0; i < unvisitedPoints.length; i++) {
            let pt = unvisitedPoints[i]; if (pt.isolated) continue
            let verts = polygonVertices[pt.id]
            if (verts && verts.length > 0) { for (let j = 0; j < verts.length; j++) allVerts.push({ vert: verts[j], ptId: pt.id }) }
            else allVerts.push({ vert: { x: pt.x, y: pt.y }, ptId: pt.id })
        }
        if (allVerts.length === 0) { let fb = getClosestPoint(pos, unvisitedPoints); onDone(fb ? fb.point : null); return }
        let locations = allVerts.map(function(e) { return { lon: e.vert.x, lat: e.vert.y } })
        let body = JSON.stringify({ locations: locations, costing: "pedestrian" }); let url = "https://valhalla1.openstreetmap.de/locate"
        var req = new XMLHttpRequest()
        req.timeout = 8000; req.ontimeout = function() { let fb = getClosestPoint(pos, unvisitedPoints); onDone(fb ? fb.point : null) }
        req.onerror = req.ontimeout
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (navState !== snapNavState) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText); let bestPerPt = {}
                    for (let k = 0; k < json.length && k < allVerts.length; k++) {
                        let entry = json[k]; let roadDist = 1e9; let roadSpeed = 5
                        if (entry && entry.edges && entry.edges.length > 0) {
                            let edge = entry.edges[0]
                            if (edge.correlated_lat !== undefined && edge.correlated_lon !== undefined) roadDist = getDistMeters(allVerts[k].vert, { x: edge.correlated_lon, y: edge.correlated_lat })
                            if (edge.speed !== undefined) roadSpeed = edge.speed
                            else if (edge.road_class !== undefined) {
                                let rc = edge.road_class
                                if (rc === "motorway") roadSpeed = 130; else if (rc === "trunk") roadSpeed = 110; else if (rc === "primary") roadSpeed = 90; else roadSpeed = 50
                            }
                        }
                        let ptId = allVerts[k].ptId
                        if (!bestPerPt[ptId] || roadDist < bestPerPt[ptId].roadDist) bestPerPt[ptId] = { vert: allVerts[k].vert, roadDist: roadDist, roadSpeed: roadSpeed }
                    }
                    let bestTarget = null; let bestScore = 1e9
                    for (let ptId in bestPerPt) {
                        let b = bestPerPt[ptId]; let distToMe = getDistMeters(pos, b.vert)
                        let pedestrianPenalty = b.roadDist > 30 ? b.roadDist * 2 : 0
let currentScore = distToMe + pedestrianPenalty
                        if (currentScore < bestScore) {
                            bestScore = currentScore; let pt = unvisitedPoints.find(p => p.id === parseInt(ptId) || p.id === ptId)
                            if (pt) bestTarget = { id: pt.id, x: b.vert.x, y: b.vert.y, onRoute: b.roadDist < 30, roadDist: b.roadDist, isolated: pt.isolated }
                        }
                    }
                    if (!bestTarget) { let fb = getClosestPoint(pos, unvisitedPoints); bestTarget = fb ? fb.point : null }
                    onDone(bestTarget); return
                } catch(e) { console.log("Erreur parsing Valhalla: " + e) }
            }
        }
        req.open("POST", url); req.setRequestHeader("Content-Type", "application/json"); req.send(body)
    }

    function checkAlternativeFootAccess(target, currentWalkDist, onResult) {
        let verts = polygonVertices[target.id]; if (!verts || verts.length === 0) { onResult(currentWalkDist, null); return }
        let locations = verts.map(function(v) { return { lon: v.x, lat: v.y } }); let body = JSON.stringify({ locations: locations, costing: "auto" })
        var req = new XMLHttpRequest()
        req.timeout = 5000; req.ontimeout = function() { onResult(currentWalkDist, null) }; req.onerror = req.ontimeout
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText); let bestRoadDist = 1e9; let bestVert = null
                    for (let k = 0; k < json.length && k < verts.length; k++) {
                        let entry = json[k]
                        if (entry && entry.edges && entry.edges.length > 0) {
                            let edge = entry.edges[0]
                            if (edge.correlated_lat !== undefined && edge.correlated_lon !== undefined) {
                                let rd = getDistMeters(verts[k], { x: edge.correlated_lon, y: edge.correlated_lat })
                                if (rd < bestRoadDist) { bestRoadDist = rd; bestVert = verts[k] }
                            }
                        }
                    }
                    onResult(bestRoadDist, bestVert); return
                } catch(e) {}
            }
            onResult(currentWalkDist, null)
        }
        req.open("POST", "https://valhalla1.openstreetmap.de/locate"); req.setRequestHeader("Content-Type", "application/json"); req.send(body)
    }

    function getPointsInWalkRadius(parkPos, points) {
        if (!parkPos || !points) return []
        return points.filter(function(p) { return getDistMeters(parkPos, p) <= walkRadius })
    }

    function valhallaFootRequest(start, end, callback) {
        let straightDist = getDistMeters(start, end); let url = "https://valhalla1.openstreetmap.de/route"
        let body = JSON.stringify({
            locations: [{ lon: start.x, lat: start.y, type: "break" }, { lon: end.x, lat: end.y, type: "break" }],
            costing: "pedestrian",
            costing_options: { pedestrian: { use_ferry: 0.0, use_living_streets: 1.0, use_tracks: 1.0, use_hills: 0.5, service_penalty: 0.0, walkway_factor: 0.8 } },
            directions_options: { units: "kilometers" }
        })
        var req = new XMLHttpRequest()
        req.timeout = 5000; req.ontimeout = function() { callback(null) }; req.onerror = function() { callback(null) }
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText)
                    if (json.trip && json.trip.legs && json.trip.legs.length > 0) {
                        let coords = decodePolyline6(json.trip.legs[0].shape)
                        if (coords && coords.length >= 2) {
                            let routeDist = 0
                            for (let i = 0; i < coords.length - 1; i++) routeDist += getDistMeters({ x: coords[i][0], y: coords[i][1] }, { x: coords[i+1][0], y: coords[i+1][1] })
                            if (routeDist <= straightDist * 4) { callback(coords); return }
                        }
                    }
                } catch(e) {}
            }
            callback(null)
        }
        req.open("POST", url); req.setRequestHeader("Content-Type", "application/json"); req.send(body)
    }

    function fetchFootRoute(start, end) {
    let routingEnd = (end.walkX !== undefined && end.walkY !== undefined) ? { x: end.walkX, y: end.walkY } : end
    drawDirectLine(start, end, footRendererPlugin)
    valhallaFootRequest(start, routingEnd, function(coords) {
        _footFetchPending = false
        if (navState !== "WALKING_TO_POI" && navState !== "RETURNING_TO_CAR") return
            if (coords && coords.length >= 2) {
                let distStartToEnd = getDistMeters(start, routingEnd)
                let secondPt = { x: coords[1][0], y: coords[1][1] }
                if (getDistMeters(secondPt, routingEnd) > distStartToEnd * 1.5 + 30) { lastFootRouteCoords = null; drawDirectLine(start, end, footRendererPlugin); mapCanvas.refresh(); return }
                coords[0] = [start.x, start.y]
                let snapEnd = { x: coords[coords.length-1][0], y: coords[coords.length-1][1] }
                if (getDistMeters(snapEnd, end) > 5) coords = coords.concat([[end.x, end.y]])
                lastFootRouteCoords = coords; drawLineFromCoords(coords, footRendererPlugin); drawArrows(coords, footArrowRendererPlugin)
            } else { lastFootRouteCoords = null; drawDirectLine(start, end, footRendererPlugin) }
       //     mapCanvas.refresh()
        })
    }

    function trimFootRouteToCurrentPos(pos) {
        if (!lastFootRouteCoords || lastFootRouteCoords.length < 2) return false
        let minDist = 1e9; let closestIdx = 0
        for (let i = 0; i < lastFootRouteCoords.length; i++) {
            let d = getDistMeters(pos, { x: lastFootRouteCoords[i][0], y: lastFootRouteCoords[i][1] })
            if (d < minDist) { minDist = d; closestIdx = i }
        }
        if (closestIdx === 0) return false
        lastFootRouteCoords = lastFootRouteCoords.slice(closestIdx)
        if (lastFootRouteCoords.length >= 2) drawLineFromCoords(lastFootRouteCoords, footRendererPlugin)
        return true
    }

    function fetchOsrmRoute(start, end) {
        let snapNavState = navState; let snapTarget = currentTarget
        valhallaRequest(start, end, snapNavState, snapTarget, function(coords, snap, distOffRoad) {
            if (navState !== snapNavState || currentTarget !== snapTarget) return
            applyRouteResult(start, end, coords, snap, distOffRoad, snapNavState, snapTarget)
        })
    }

    function decodePolyline6(encoded) {
        let coords = []; let index = 0, lat = 0, lng = 0
        while (index < encoded.length) {
            let b, shift = 0, result = 0
            do { b = encoded.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
            let dlat = (result & 1) ? ~(result >> 1) : (result >> 1); lat += dlat; shift = 0; result = 0
            do { b = encoded.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
            let dlng = (result & 1) ? ~(result >> 1) : (result >> 1); lng += dlng; coords.push([lng / 1e6, lat / 1e6])
        }
        return coords
    }

    function valhallaRequest(start, end, snapNavState, snapTarget, callback) {
        let url = "https://valhalla1.openstreetmap.de/route"
        let body = JSON.stringify({
            locations: [{ lon: start.x, lat: start.y, type: "break" }, { lon: end.x, lat: end.y, type: "break" }],
            costing: "auto", costing_options: { auto: { use_tracks: 1.0, use_roads: 0.8, use_ferry: 0.0, top_speed: 80 } },
            directions_options: { units: "kilometers" }
        })
        var req = new XMLHttpRequest()
        req.timeout = 4000; req.ontimeout = function() { callback(null, null, 1e9) }; req.onerror = function() { callback(null, null, 1e9) }
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (navState !== snapNavState || currentTarget !== snapTarget) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText)
                    if (json.trip && json.trip.legs && json.trip.legs.length > 0) {
                        let coords = decodePolyline6(json.trip.legs[0].shape)
                        if (coords && coords.length >= 2) {
                            let snap = { x: coords[coords.length-1][0], y: coords[coords.length-1][1] }
                            callback(coords, snap, getDistMeters(snap, end)); return
                        }
                    }
                } catch(e) {}
            }
            callback(null, null, 1e9)
        }
        req.open("POST", url); req.setRequestHeader("Content-Type", "application/json"); req.send(body)
    }

    function applyRouteResult(start, end, coords, snap, distOffRoad, snapNavState, snapTarget) {
        if (!coords) { drawDirectLine(start, end, carRendererPlugin); return }
        if (navState !== snapNavState || currentTarget !== snapTarget) return
        let extCoords = coords
        if (coords.length >= 2) {
            let p1 = coords[coords.length - 2], p2 = coords[coords.length - 1]
            let dx = p2[0] - p1[0], dy = p2[1] - p1[1]
            let segLen = getDistMeters({ x: p1[0], y: p1[1] }, { x: p2[0], y: p2[1] })
            if (segLen > 0) {
                let mPerDegLat = 111320, mPerDegLon = Math.cos(p2[1] * Math.PI / 180) * 111320
                let extLon = p2[0] + (dx / segLen) * (10 / mPerDegLon), extLat = p2[1] + (dy / segLen) * (10 / mPerDegLat)
                extCoords = coords.concat([[extLon, extLat]])
            }
        }
        drawLineFromCoords(extCoords, carRendererPlugin)
drawArrows(extCoords, arrowRenderer)
lastRouteCoords = coords
        refinePolygonTargetsFromRoute(coords, snap)

        if (distOffRoad > 20 && !(currentTarget && currentTarget.onRoute)) {
    routeHasFootSegment = true
    drawLineFromCoords(coords, carRendererPlugin)
    drawArrows(coords, arrowRenderer)
    drawDirectLine(snap, currentTarget, footRendererPlugin)
    if (getDistMeters(start, snap) < 30 && navState === "DRIVING") {
    navState = "WALKING_TO_POI"
    parkedLocation = snap
    lastFootRouteCoords = null; lastFootPos = snap
    showHudMessage(tr("Fin de route.\nRecherche accès piéton..."), true)
    let targetToTransition = currentTarget
    findBestWalkingBoundaryPoint(targetToTransition, function(newTarget) {
        if (navState !== "WALKING_TO_POI") return
        currentTarget = newTarget
        fetchFootRoute(snap, newTarget)
        showHudMessage(tr("Voiture stationnée.\nFinir à pied."), true)
        updatePolygonCenterRenderer(); updateArrowRenderer(); mapCanvas.refresh()
    })
}
} else {
    routeHasFootSegment = false; clearGeometry(footRendererPlugin)
}
     //   mapCanvas.refresh()
    } 

    function refinePolygonTargetsFromRoute(routeCoords, snap) {
        if (!routeCoords || routeCoords.length < 2) return
        let hasParking = parkedLocation && parkedLocation.x; let refCoords = routeCoords; let cumDist = 0
        for (let i = routeCoords.length - 2; i >= 1; i--) {
            cumDist += getDistMeters({ x: routeCoords[i][0], y: routeCoords[i][1] }, { x: routeCoords[i+1][0], y: routeCoords[i+1][1] })
            if (cumDist > 120) { refCoords = routeCoords.slice(0, i + 1); break }
        }
        if (refCoords.length < 2) refCoords = routeCoords.slice(0, routeCoords.length - 1)
        if (refCoords.length < 2) return
        let updated = unvisitedPoints.map(function(pt) {
            let verts = polygonVertices[pt.id]; if (!verts || verts.length === 0) return pt
            let bestPt = null; let bestDist = 1e9
            if (hasParking) {
                for (let j = 0; j < verts.length; j++) {
                    let d = getDistMeters(parkedLocation, verts[j]) + minDistToRouteLine(verts[j], refCoords)
                    if (d < bestDist) { bestDist = d; bestPt = verts[j] }
                }
            } else {
                for (let j = 0; j < verts.length; j++) {
                    let d = minDistToRouteLine(verts[j], refCoords)
                    if (d < bestDist) { bestDist = d; bestPt = verts[j] }
                }
                if (bestDist > 250) return pt
            }
            if (!bestPt) return pt
            return { id: pt.id, x: bestPt.x, y: bestPt.y, onRoute: minDistToRouteLine(bestPt, refCoords) < 20, isolated: pt.isolated }
        })
        unvisitedPoints = updated
        if (currentTarget) {
            let refreshed = unvisitedPoints.find(function(p) { return p.id === currentTarget.id })
            if (refreshed) currentTarget = refreshed
        }
        updateOnRouteRenderer(); updatePolygonCenterRenderer(); updateArrowRenderer() //; mapCanvas.refresh()
    }

    function chainIsolatedPoints(rawPoints) {
        let isolated = rawPoints.filter(function(p) { return p.isolated }); let accessible = rawPoints.filter(function(p) { return !p.isolated })
        if (isolated.length === 0 || accessible.length === 0) return
        for (let i = 0; i < isolated.length; i++) {
            let iso = isolated[i]; let isoVerts = polygonVertices[iso.id]; if (!isoVerts || isoVerts.length === 0) continue
            let bestNeighborVert = null; let bestPairDist = 1e9; let bestIsoVert = null
            for (let j = 0; j < accessible.length; j++) {
                let acc = accessible[j]; let accVerts = (polygonVertices[acc.id] && polygonVertices[acc.id].length > 0) ? polygonVertices[acc.id] : [{ x: acc.x, y: acc.y }]
                for (let v = 0; v < accVerts.length; v++) {
                    for (let w = 0; w < isoVerts.length; w++) {
                        let d = getDistMeters(accVerts[v], isoVerts[w])
                        if (d < bestPairDist) { bestPairDist = d; bestNeighborVert = accVerts[v]; bestIsoVert = isoVerts[w] }
                    }
                }
            }
            if (!bestIsoVert) continue
            let idx = rawPoints.indexOf(iso); if (idx >= 0) rawPoints[idx] = { id: iso.id, x: bestIsoVert.x, y: bestIsoVert.y, onRoute: false, isolated: true, chained: true }
        }
    }

    function shouldParkHere(myPos, remainingPts) {
        if (!remainingPts || remainingPts.length === 0) return false
        let inRadius = getPointsInWalkRadius(myPos, remainingPts)
        if (inRadius.length === 0) return false
        return !inRadius.find(function(p) { return !p.isolated })
    }

    function updatePolygonCenterRenderer() {
        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)")
        if (targetJustValidated) {
            if (_lastPolygonWkt !== "") { _lastPolygonWkt = ""; if (empty) polygonCenterRendererPlugin.geometryWrapper.qgsGeometry = empty }
            targetJustValidated = false; resetPolygonTimer.restart(); return
        }
        let candidates = unvisitedPoints.filter(function(p) { return p.onRoute })
        if (navState === "WALKING_TO_POI" && currentTarget && !candidates.find(function(p) { return p.id === currentTarget.id })) candidates = candidates.concat([currentTarget])
        if (candidates.length === 0) { if (_lastPolygonWkt !== "") { _lastPolygonWkt = ""; if (empty) polygonCenterRendererPlugin.geometryWrapper.qgsGeometry = empty } ; return }
        let polygons = []
        for (let i = 0; i < candidates.length; i++) {
            let verts = polygonVertices[candidates[i].id]; if (!verts || verts.length < 3) continue
            let ring = verts.map(function(v) { return v.x.toFixed(6) + " " + v.y.toFixed(6) }); let first = verts[0], last = verts[verts.length - 1]
            if (first.x !== last.x || first.y !== last.y) ring.push(first.x.toFixed(6) + " " + first.y.toFixed(6))
            polygons.push("((" + ring.join(",") + "))")
        }
        if (polygons.length === 0) { if (_lastPolygonWkt !== "") { _lastPolygonWkt = ""; if (empty) polygonCenterRendererPlugin.geometryWrapper.qgsGeometry = empty } ; return }
        let wkt = polygons.length === 1 ? "POLYGON" + polygons[0] : "MULTIPOLYGON(" + polygons.join(",") + ")"
        if (wkt === _lastPolygonWkt) return
        _lastPolygonWkt = wkt; let geom = GeometryUtils.createGeometryFromWkt(wkt)
        if (geom) polygonCenterRendererPlugin.geometryWrapper.qgsGeometry = geom
    }

    function updateArrowRenderer() {
    // Les flèches sont gérées par drawArrows() et stopNavigation() uniquement
}

function buildArrowsWkt(coords, intervalMeters) {
    if (!coords || coords.length < 2) return null
    let step = intervalMeters || 150
    let arrowSizeM = 20
    let maxArrows = 15
    let lines = []; let accumulated = 0
    let mPerDegLat = 111320
    for (let i = 0; i < coords.length - 1; i++) {
        let ax = coords[i][0], ay = coords[i][1]
        let bx = coords[i+1][0], by = coords[i+1][1]
        let segLen = getDistMeters({ x: ax, y: ay }, { x: bx, y: by })
        accumulated += segLen
        if (accumulated < step) continue
        accumulated = 0
        let mPerDegLon = Math.cos(ay * Math.PI / 180) * mPerDegLat
        if (mPerDegLon < 1) continue
        let dxDeg = bx - ax, dyDeg = by - ay
        let dxM = dxDeg * mPerDegLon, dyM = dyDeg * mPerDegLat
        let lenM = Math.sqrt(dxM * dxM + dyM * dyM)
        if (lenM < 1) continue
        let uxM = dxM / lenM, uyM = dyM / lenM
        let tipX = ax + dxDeg * 0.6, tipY = ay + dyDeg * 0.6
        let halfArm = arrowSizeM * 0.35
        let angle = 2.65
        let cos1 = Math.cos(angle), sin1 = Math.sin(angle)
        let cos2 = Math.cos(-angle), sin2 = Math.sin(-angle)
        let arm1xM = uxM * cos1 - uyM * sin1, arm1yM = uxM * sin1 + uyM * cos1
        let arm2xM = uxM * cos2 - uyM * sin2, arm2yM = uxM * sin2 + uyM * cos2
        let p1 = (tipX + arm1xM * halfArm / mPerDegLon).toFixed(7) + " " + (tipY + arm1yM * halfArm / mPerDegLat).toFixed(7)
        let p2 = (tipX + arm2xM * halfArm / mPerDegLon).toFixed(7) + " " + (tipY + arm2yM * halfArm / mPerDegLat).toFixed(7)
        let tip = tipX.toFixed(7) + " " + tipY.toFixed(7)
        lines.push("((" + p1 + "," + tip + "," + p2 + "," + p1 + "))")
    }
    if (lines.length === 0) return null
if (lines.length > maxArrows) {
    let stride = Math.ceil(lines.length / maxArrows)
    let reduced = []
    for (let i = 0; i < lines.length; i += stride) reduced.push(lines[i])
    lines = reduced
}
return "MULTIPOLYGON(" + lines.join(",") + ")"
}

function drawArrows(coords, renderer) {
    if (!coords || coords.length < 2) return
    let totalDist = 0
    for (let i = 0; i < coords.length - 1; i++)
        totalDist += getDistMeters({ x: coords[i][0], y: coords[i][1] }, { x: coords[i+1][0], y: coords[i+1][1] })
    let targetCount = 7
    let interval = Math.max(30, totalDist / targetCount)
    let wkt = buildArrowsWkt(coords, interval)
    if (!wkt) return
    if (wkt === _lastArrowWkt) return
    _lastArrowWkt = wkt
    let geom = GeometryUtils.createGeometryFromWkt(wkt)
    if (geom) renderer.geometryWrapper.qgsGeometry = geom
}

    // --- 10. DESSIN ---
    function drawDirectLine(start, end, renderer) {
        let wkt = "LINESTRING(" + start.x.toFixed(6) + " " + start.y.toFixed(6) + ", " + end.x.toFixed(6) + " " + end.y.toFixed(6) + ")"
        let geom = GeometryUtils.createGeometryFromWkt(wkt); if(geom) renderer.geometryWrapper.qgsGeometry = geom
    }

    function drawLineFromCoords(coords, renderer) {
    if (!coords || coords.length < 2) return
    let pts = []
    for (let i = 0; i < coords.length; i++) pts.push(coords[i][0] + " " + coords[i][1])
    let wkt = "LINESTRING(" + pts.join(",") + ")"
    if (renderer === carRendererPlugin) {
        if (wkt === _lastCarRouteWkt) return
        _lastCarRouteWkt = wkt
    } else if (renderer === footRendererPlugin) {
        if (wkt === _lastFootRouteWkt) return
        _lastFootRouteWkt = wkt
    }
    let geom = GeometryUtils.createGeometryFromWkt(wkt)
    if (geom) renderer.geometryWrapper.qgsGeometry = geom
}

    function clearGeometry(renderer) {
        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)") 
        if(empty) renderer.geometryWrapper.qgsGeometry = empty
    }

    function trimRouteToCurrentPos(pos) {
        if (!lastRouteCoords || lastRouteCoords.length < 2) return false
        let minDist = 1e9; let closestIdx = 0
        for (let i = 0; i < lastRouteCoords.length; i++) {
            let d = getDistMeters(pos, { x: lastRouteCoords[i][0], y: lastRouteCoords[i][1] })
            if (d < minDist) { minDist = d; closestIdx = i }
        }

        if (routeHasFootSegment) {
            let remainingDist = 0
            for (let j = closestIdx; j < lastRouteCoords.length - 1; j++) {
                remainingDist += getDistMeters({ x: lastRouteCoords[j][0], y: lastRouteCoords[j][1] }, { x: lastRouteCoords[j+1][0], y: lastRouteCoords[j+1][1] })
            }
            // --- TRANSITION SMART ---
            if (remainingDist < 15 && navState === "DRIVING") {
                findBestWalkingBoundaryPoint(currentTarget, function(newTarget) {
    if (navState !== "DRIVING" || !newTarget) return
    
    currentTarget = newTarget
parkedLocation = { x: lastRouteCoords[lastRouteCoords.length-1][0], y: lastRouteCoords[lastRouteCoords.length-1][1] }
navState = "WALKING_TO_POI"
lastFootRouteCoords = null; lastFootPos = parkedLocation

    if (lastRouteCoords && lastRouteCoords.length >= 2) {
        let newCarRoute = []
        for (let k = 0; k < lastRouteCoords.length; k++) {
            newCarRoute.push([lastRouteCoords[k][0], lastRouteCoords[k][1]])
            if (getDistMeters({ x: lastRouteCoords[k][0], y: lastRouteCoords[k][1] }, walkEntry) < 30) break
        }
        if (newCarRoute.length >= 2) drawLineFromCoords(newCarRoute, carRendererPlugin)
    }
    fetchFootRoute(parkedLocation, currentTarget)
    showHudMessage(tr("Voiture stationnée.\nFinir à pied."), true)
})
                return true
            }
        }
        if (closestIdx === 0) return false
let remaining = lastRouteCoords.slice(closestIdx); lastRouteCoords = remaining
if (remaining.length >= 2 && closestIdx > 3) drawLineFromCoords(remaining, carRendererPlugin)
return true
    }

    // --- 11. UTILS ---
    function getCurrentGpsPosition() {
        if (iface.positionSource && iface.positionSource.active) {
            let gpsPt = iface.positionSource.sourcePosition
            if (gpsPt && (gpsPt.x !== 0 || gpsPt.y !== 0)) return { x: gpsPt.x, y: gpsPt.y }
        }
        try {
            let locatorItem = iface.findItemByObjectName("locator")
            if (locatorItem && locatorItem.positionInformation) {
                let pi = locatorItem.positionInformation
                if (pi.latitude !== undefined && pi.longitude !== undefined && (pi.latitude !== 0 || pi.longitude !== 0)) return { x: pi.longitude, y: pi.latitude }
            }
        } catch(e) {}
        try {
            let navItem = iface.findItemByObjectName("navigation")
            if (navItem && navItem.location && (navItem.location.x !== 0 || navItem.location.y !== 0)) {
                let wgs = GeometryUtils.reprojectPointToWgs84(navItem.location, mapCanvas.mapSettings.destinationCrs)
                if (wgs && (wgs.x !== 0 || wgs.y !== 0)) return { x: wgs.x, y: wgs.y }
            }
        } catch(e) {}
        return null
    }

    function getMapCenter() {
        let extent = mapCanvas.mapSettings.extent; let cx = (extent.xMinimum + extent.xMaximum) / 2; let cy = (extent.yMinimum + extent.yMaximum) / 2
        let wkt = "POINT(" + cx + " " + cy + ")"; let g = GeometryUtils.createGeometryFromWkt(wkt)
        if (g) { let p = GeometryUtils.centroid(g); let w = GeometryUtils.reprojectPointToWgs84(p, mapCanvas.mapSettings.destinationCrs)
        if (w && (w.x !== 0 || w.y !== 0)) return { x: w.x, y: w.y } }
        return null
    }

    function getCrosshairPosition() {
        try {
            let locatorItem = iface.findItemByObjectName("locator")
            if (locatorItem && locatorItem.currentCoordinate) {
                let coord = locatorItem.currentCoordinate; let wgs = GeometryUtils.reprojectPointToWgs84(coord, mapCanvas.mapSettings.destinationCrs)
                if (wgs && (wgs.x !== 0 || wgs.y !== 0)) return { x: wgs.x, y: wgs.y }
            }
        } catch(e) {}
        return getMapCenter()
    }

    function getDistMeters(pt1, pt2) {
        if (!pt1 || !pt2) return 100000; var R = 6371000; var dLat = (pt2.y - pt1.y) * (Math.PI/180); var dLon = (pt2.x - pt1.x) * (Math.PI/180)
        var a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(pt1.y * (Math.PI/180)) * Math.cos(pt2.y * (Math.PI/180)) * Math.sin(dLon/2) * Math.sin(dLon/2)
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); return R * c
    }
}