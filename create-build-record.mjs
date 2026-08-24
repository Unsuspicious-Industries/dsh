import { execSync } from 'node:child_process';
import { resolve, mkdirSync } from 'node:path';
import { writeFileSync } from 'node:fs';

// Get commit hash
const commitHash = execSync('git rev-parse HEAD', { cwd: '/workspace/deepseek-harness', encoding: 'utf8' }).trim().slice(0, 7).toLowerCase();
console.log('Commit hash:', commitHash);

// Create .dsh-build directory
const buildDir = resolve('/workspace/deepseek-harness', '.dsh-build');
mkdirSync(buildDir, { recursive: true });

// Create client build environment record
const clientBuildRecord = {
  formatVersion: 1,
  environment: {
    DSH_CLIENT_BUILD_PROFILE: 'official',
    DSH_CLIENT_TITLE: 'DeepSeek Harness',
    DSH_CLIENT_COMMIT_HASH: commitHash
  },
  artifacts: {
    fileCount: 0,  // Will be updated later
    sha256: ''  // Will be updated later
  }
};

const recordPath = resolve(buildDir, 'client-build-environment.json');
writeFileSync(recordPath, JSON.stringify(clientBuildRecord, null, 2) + '\n');
console.log('Created client build record at:', recordPath);