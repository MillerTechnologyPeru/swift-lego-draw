import LegoDrawFile

/// A simple brick-shaped LDraw model embedded directly in the playground so no
/// external parts library is required.  The geometry is a 40×24×40 LDU box
/// (roughly a 2×2 LEGO brick body, without studs) expressed as BFC-certified
/// CCW quads and a cylinder top for the single stud.
let embeddedModelLDraw = """
0 Playground Brick
0 BFC CERTIFY CCW
4 4 -20 0 -20  20 0 -20  20 0 20  -20 0 20
4 4 -20 24 -20  -20 24 20  20 24 20  20 24 -20
4 4 -20 0 -20  -20 24 -20  20 24 -20  20 0 -20
4 4  20 0 -20   20 24 -20  20 24 20   20 0 20
4 4  20 0  20   20 24  20 -20 24 20  -20 0 20
4 4 -20 0  20  -20 24  20 -20 24 -20 -20 0 -20
"""

func makeEmbeddedModel(colorCode: Int16 = 4, colorTable: LDrawColorTable) throws -> (ResolvedLDrawModel, LDrawResolvedColor) {
    let defaultColor = colorTable.color(forCode: colorCode)
        ?? LDrawResolvedColor(
            name: "Red", code: 4,
            red: 199, green: 20, blue: 20,
            edgeRed: 0, edgeGreen: 0, edgeBlue: 0
        )
    let file = try LDrawParser.parseFile(embeddedModelLDraw)
    let resolver = LDrawModelResolver(resolver: NoOpResolver(), missingPartPolicy: .omit)
    let model = try resolver.resolve(file)
    return (model, defaultColor)
}

private struct NoOpResolver: LDrawPartResolver {
    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? { nil }
}
