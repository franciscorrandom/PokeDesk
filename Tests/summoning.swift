import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
func channels(_ f: PetSummonFrame) -> [Double] {
    [f.petAmount, f.petOpacity, f.whiten, f.lidOpen, f.ballOpacity, f.glow, f.beam, f.sparks, f.progress]
}
for phase in PetSummonPhase.allCases {
    let start = PetSummonFrame(phase: phase, time: 0)
    let end = PetSummonFrame(phase: phase, time: phase.duration)
    check(start.ballOpacity == 1 && start.lidOpen == 0, "La Pokébola llega cerrada")
    check(end.ballOpacity == 0 && end.lidOpen == 0 && end.glow == 0 && end.whiten == 0 && end.beam == 0 && end.sparks == 0, "El efecto termina sin luz ni residuos")
    check(end.petAmount == (phase == .release ? 1 : 0), "El Pokémon llega al destino exacto")
    check(end.petOpacity == (phase == .release ? 1 : 0), "No queda parcialmente transparente")
    check(channels(PetSummonFrame(phase: phase, time: -10)) == channels(start), "Un reloj previo se limita al inicio")
    check(channels(PetSummonFrame(phase: phase, time: .nan)) == channels(start), "Un reloj no válido no altera la figura")
    check(channels(PetSummonFrame(phase: phase, time: 100)) == channels(end), "Una pausa larga finaliza el efecto")
    var previous = start
    for step in 1...Int(ceil(phase.duration*120)) {
        let frame = PetSummonFrame(phase: phase, time: Double(step)/120)
        check(channels(frame).allSatisfy { $0.isFinite && (0...1).contains($0) } && frame.ballLift.isFinite, "Todos los canales son finitos y válidos")
        let deltas = zip(channels(frame), channels(previous)).map { abs($0-$1) }
        check(deltas.max()! < 0.12, "No hay saltos bruscos entre fotogramas")
        if phase == .release { check(frame.petAmount >= previous.petAmount, "La aparición crece sin retroceder") }
        else { check(frame.petAmount <= previous.petAmount, "La retirada se contrae sin retroceder") }
        previous = frame
    }
    let peak = PetSummonFrame(phase: phase, time: phase == .release ? 1.05 : 0.8)
    check(peak.lidOpen > 0.95 && peak.whiten > 0.95 && peak.glow > 0.95, "La materialización ocurre con la Pokébola abierta y luz activa")
}
print("\(checks) verificaciones de aparición y retirada pasaron")
