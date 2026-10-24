import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
var motion = Arcanine3DMotion()
motion.request(.chaseTail, at: 1)
check(motion.clip == .chaseTail, "El giro autorizado comienza")
motion.request(.alert, at: 2)
check(motion.clip == .alert, "Una reunión interrumpe el giro")
motion.click(at: 2.1)
check(motion.clip == .alert, "El clic no oculta el aviso")
motion.request(.celebration, at: 3)
check(motion.clip == .alert, "La celebración espera al aviso")
motion.tick(at: 6.1)
check(motion.clip == .celebration, "La celebración pendiente se reproduce")
motion.tick(at: 10)
check(motion.clip == .idle, "Cada gesto vuelve a reposo")
motion.request(.chaseTail, at: 11)
check(motion.clip == .idle, "La persecución no se repite antes de tres minutos")
motion.request(.chaseTail, at: 181)
check(motion.clip == .chaseTail, "La persecución vuelve tras el intervalo")
motion.tick(at: 186)
motion.focusing = true
motion.request(.chaseTail, at: 400)
check(motion.clip == .idle, "El giro automático se evita durante el foco")
motion.request(.chaseTail, at: 401, manual: true)
check(motion.clip == .chaseTail, "El usuario puede probar el giro explícitamente")
motion.setEnabled(false, at: 402)
motion.request(.alert, at: 403)
motion.click(at: 403)
motion.tick(at: 1000)
check(motion.clip == .idle, "Reducir movimiento conserva la postura estática")
motion.setEnabled(true, at: 1001)
motion.focusing = false
motion.alerting = true
motion.tick(at: 1100)
check(motion.clip == .idle, "No hay gestos ocasionales mientras se lee un aviso")
motion.alerting = false
var previous: ArcanineClip?
for index in 0..<100 {
    let t = 1200 + Double(index) * 10
    motion.click(at: t)
    check(motion.clip != previous, "Los clics consecutivos varían el gesto")
    previous = motion.clip
    motion.tick(at: t + 6)
    check(motion.clip == .idle, "El gesto termina sin quedar pegado")
}
var focus = Arcanine3DMotion()
focus.focusing = true
focus.request(.idle, at: 0)
focus.tick(at: 70)
check(focus.clip == .idle, "El foco reduce la frecuencia de gestos")
focus.tick(at: 120)
check([ArcanineClip.curious, .sniff].contains(focus.clip), "El foco permite solo gestos tranquilos")
check(PetRotation.normalized(.infinity) == 0 && PetRotation.normalized(.nan) == 0, "Un ángulo no válido no altera la figura")
check(abs(PetRotation.dragged(from: 0, horizontalPoints: 112.5) - .pi / 2) < 0.000001, "El arrastre horizontal gira de forma gradual")
for turns in -20...20 {
    let angle = Double(turns) * 2 * .pi + 0.4
    check(abs(PetRotation.normalized(angle) - 0.4) < 0.000001, "Muchos giros conservan un ángulo estable")
}
for clip in ArcanineClip.allCases {
    var manual = Arcanine3DMotion()
    manual.focusing = true
    manual.alerting = true
    manual.request(.alert, at: 0)
    manual.request(clip, at: 1, manual: true)
    check(manual.clip == clip, "Cada animación se puede pedir explícitamente incluso durante el foco")
    if clip != .idle {
        manual.tick(at: 1 + clip.duration - 0.01)
        check(manual.clip == clip, "Cada gesto dispone de su duración completa")
        manual.tick(at: 1 + clip.duration + 0.01)
        check(manual.clip == .idle, "Cada gesto, incluidas caricias y sentarse, vuelve a reposo")
    }
}
var psychic = Arcanine3DMotion(character: .mewtwo)
for clip in PetCharacter.mewtwo.clips {
    psychic.request(clip, at: 0, manual: true)
    check(psychic.clip == clip, "Mewtwo permite todos sus gestos manuales")
    psychic.tick(at: 10)
}
psychic.request(.idle, at: 0)
psychic.request(.chaseTail, at: 1, manual: true)
check(psychic.clip == .idle, "Mewtwo no recibe la persecución canina")
for index in 0..<50 {
    let t = Double(index) * 200
    psychic.click(at: t)
    check(PetCharacter.mewtwo.clips.contains(psychic.clip), "Cada clic usa un gesto compatible con Mewtwo")
    psychic.tick(at: t + 10)
}
psychic.focusing = true
for index in 0..<8 {
    let t = 20_000 + Double(index) * 200
    psychic.tick(at: t)
    check(psychic.clip == .curious, "Mewtwo mantiene gestos tranquilos durante el foco, sin atascarse al repetir el único gesto disponible")
    psychic.tick(at: t + 6)
}
psychic.request(.alert, at: 30_000)
psychic.click(at: 30_001)
check(psychic.clip == .alert, "Los avisos de reunión conservan prioridad con Mewtwo")
for character in [PetCharacter.lucario, .gengar] {
    var newcomer = Arcanine3DMotion(character: character)
    for clip in character.clips {
        newcomer.request(clip, at: 0, manual: true)
        check(newcomer.clip == clip, "Los nuevos compañeros aceptan todo su repertorio")
        newcomer.tick(at: clip.duration + 0.01)
        check(newcomer.clip == .idle, "Cada gesto nuevo vuelve al reposo")
    }
    newcomer.request(.chaseTail, at: 20, manual: true)
    check(newcomer.clip == .idle, "Los nuevos compañeros no reciben el giro canino")
    newcomer.request(.alert, at: 21)
    newcomer.click(at: 22)
    check(newcomer.clip == .alert, "Los avisos mantienen prioridad con los nuevos compañeros")
}
print("\(checks) comprobaciones 3D correctas")
let screens = [FloatingRect(x: 0, y: 0, width: 1440, height: 900),
               FloatingRect(x: -1440, y: 24, width: 1440, height: 876),
               FloatingRect(x: 0, y: -900, width: 1024, height: 768)]
for screen in screens {
    for x in [screen.x, screen.midX, screen.maxX] {
        for y in [screen.y, screen.y + screen.height / 2, screen.maxY] {
            let menu = QuickMenuLayout.place(anchorX: x, anchorY: y, screen: screen)
            check(menu.x >= screen.x && menu.y >= screen.y && menu.maxX <= screen.maxX && menu.maxY <= screen.maxY,
                  "El arco queda dentro de la pantalla incluso en esquinas y monitores secundarios")
            for height in [252.0, 310, 360, 400] {
                let card = QuickMenuLayout.detail(width: 350, height: height, menu: menu, screen: screen)
                check(card.x >= screen.x && card.y >= screen.y && card.maxX <= screen.maxX && card.maxY <= screen.maxY,
                      "Las cuatro tarjetas rápidas quedan completas en pantalla")
            }
        }
    }
}
for index in 0..<QuickMenuLayout.buttonCount {
    let point = QuickMenuLayout.buttonCenter(index)
    check(QuickMenuLayout.containsControl(x: point.x, y: point.y), "Los siete accesos tienen una zona de clic")
}
check(!QuickMenuLayout.containsControl(x: QuickMenuLayout.width / 2, y: 94), "El centro vacío del arco permite pasar los clics")
print("\(checks) comprobaciones de movimiento y posición de accesos correctas")
