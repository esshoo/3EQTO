#!/usr/bin/env python3
"""Exercise the actual Swift DXF writer + validator contract. No CAD app required."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
exporter = (ROOT / 'RoomSurveyElectrical/DXFExporter.swift').read_text(encoding='utf-8')
# The self-contained writer is the final declaration of this source file.
writer = exporter[exporter.index('private struct DXFWriter {'):]
harness = r'''
@main
struct DXFContractTest {
    static func main() throws {
        var dxf = DXFWriter()
        dxf.pair(999, "3ERoomElectrical v1.9.10 MODEL_SPACE_UTF8_2007")
        dxf.pair(0, "SECTION"); dxf.pair(2, "HEADER")
        dxf.pair(9, "$ACADVER"); dxf.pair(1, "AC1021")
        dxf.pair(9, "$DWGCODEPAGE"); dxf.pair(3, "ANSI_1252")
        dxf.pair(0, "ENDSEC")
        dxf.pair(0, "SECTION"); dxf.pair(2, "CLASSES"); dxf.pair(0, "ENDSEC")
        dxf.pair(0, "SECTION"); dxf.pair(2, "TABLES")
        dxf.pair(0, "BLOCK_RECORD"); dxf.pair(5, "31"); dxf.pair(2, "*Model_Space")
        dxf.pair(0, "ENDSEC")
        dxf.pair(0, "SECTION"); dxf.pair(2, "BLOCKS")
        dxf.pair(0, "BLOCK"); dxf.pair(330, "31"); dxf.pair(2, "*Model_Space")
        dxf.pair(0, "ENDBLK"); dxf.pair(0, "ENDSEC")
        dxf.beginEntities()
        dxf.polyline([(0,0),(4,0),(4,1),(1,1),(1,3),(0,3)], layer: "Floors", closed: true)
        dxf.line(from: (0,0), to: (4,0), layer: "Walls")
        dxf.endEntities()
        dxf.addRequiredObjects()
        dxf.endFile()
        try DXFCompatibilityValidator.validate(dxf.output)
        try dxf.output.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        var rejected = 0
        let invalid = [
            dxf.output.replacingOccurrences(of: "410\nModel\n", with: "410\nLayout1\n"),
            dxf.output.replacingOccurrences(of: "AC1021", with: "AC1015"),
            dxf.output.replacingOccurrences(of: "ACAD_GROUP", with: "BROKEN_GROUP"),
            dxf.output.replacingOccurrences(of: "330\n31\n", with: "330\n99\n")
        ]
        for candidate in invalid {
            do { try DXFCompatibilityValidator.validate(candidate) }
            catch { rejected += 1 }
        }
        precondition(rejected == invalid.count, "invalid DXF contract accepted")
        print("PASS: actual Swift DXF writer/validator: current fixture + 4 negative cases")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='3eqto-dxf-') as directory:
    temp = Path(directory)
    source = temp / 'DXFContract.swift'
    source.write_text('import Foundation\n' + writer + harness, encoding='utf-8')
    binary = temp / 'dxf-test'
    fixture = temp / 'current-contract.dxf'
    subprocess.run(['swiftc', '-swift-version', '5', str(ROOT / 'RoomSurveyElectrical/DXFCompatibilityValidator.swift'), str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(fixture)], check=True)
    subprocess.run(['python3', str(ROOT / 'Tools/check-dxf-model-space.py'), str(fixture)], check=True)
print('DXF contract checks: PASS. Full CAD reader / iPhone export tests are separate.')
