import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
const workspaceDir = path.join(process.cwd(), 'stage3-RIS与毫米波通感一体化联合优化算法方案/ppt');
const build = path.join(workspaceDir, '.build-results-20261118');
const skill = 'C:/Users/Fubuki/.codex/plugins/cache/openai-primary-runtime/presentations/26.1112.11217/skills/presentations';
process.env.RUNTIME_NODE_MODULES = 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1112-737-0_26.1112.737.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules';
const { finalizePresentation } = await import(pathToFileURL(path.join(skill, 'container_tools/artifact_tool_utils.mjs')).href);
const source = path.join(workspaceDir, 'deliverables/RIS_通感一体化_定位全流程.pptx');
const result = await finalizePresentation({
  workspaceDir,
  candidatePath: path.join(build, 'combined.candidate-v3.pptx'),
  finalPath: path.join(workspaceDir, 'deliverables/RIS_通感一体化_定位全流程_结果补充_20261118_v2.pptx'),
  pythonExecutable: 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1112-737-0_26.1112.737.0_x64__3k8sg7r9htsxt/dependencies/python/python.exe',
  integrityValidatorPath: path.join(skill, 'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath: path.join(skill, 'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs: ['--expected-slide-size-emu', '12192000,6858000', '--validate-bullet-geometry', '--validate-heading-fit', ...[12, 16, 17].flatMap(i => ['--require-native-table-slide', String(i)])],
  explicitTotalSlideCount: 18,
  requiredNativeTableOwnerSlides: [12, 16, 17],
  requiredNativeChartOwnerSlides: [13, 14, 15, 16],
  materializeLiteralChartWorkbooks: true,
  nativeChartTargetApplication: 'powerpoint',
  fontPolicy: { basis: 'reference', families: ['Microsoft YaHei'], referencePath: source, referenceSha256: createHash('sha256').update(await fs.readFile(source)).digest('hex') },
  verifyArtifactToolImport: true,
  receiptPath: path.join(build, 'finalization-v2.json'),
});
console.log(JSON.stringify(result, null, 2));
