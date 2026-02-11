#!/usr/bin/env bash
# detect_project.sh — Detect project characteristics for /uplevel audit.
#
# @decision Shell over Python: zero dependencies, fast startup, only needs
# file-existence checks and simple parsing. Python would add overhead for
# no benefit here.
#
# Usage: bash detect_project.sh [repo_root]
# Output: JSON to stdout with project metadata.

set -euo pipefail

REPO_ROOT="${1:-.}"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

# --- Helpers ---

has_file() { [[ -f "$REPO_ROOT/$1" ]]; }
has_dir()  { [[ -d "$REPO_ROOT/$1" ]]; }
has_glob() { compgen -G "$REPO_ROOT/$1" > /dev/null 2>&1; }

json_array() {
  local items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  local out="["
  for i in "${!items[@]}"; do
    [[ $i -gt 0 ]] && out+=","
    out+="\"${items[$i]}\""
  done
  out+="]"
  echo "$out"
}

json_bool() { [[ "$1" == "true" ]] && echo "true" || echo "false"; }

# --- Language Detection ---

languages=()
primary_language=""

if has_file "package.json" || has_file "tsconfig.json" || has_glob "*.ts"; then
  if has_file "tsconfig.json" || has_glob "*.ts" || has_glob "**/*.ts"; then
    languages+=("typescript")
    [[ -z "$primary_language" ]] && primary_language="typescript"
  fi
  if has_glob "*.js" || has_glob "*.jsx"; then
    # Only add JS if no TS detected, or if there are standalone JS files
    if [[ ! " ${languages[*]} " =~ " typescript " ]]; then
      languages+=("javascript")
      [[ -z "$primary_language" ]] && primary_language="javascript"
    fi
  fi
fi

if has_file "pyproject.toml" || has_file "setup.py" || has_file "requirements.txt" || has_file "Pipfile"; then
  languages+=("python")
  [[ -z "$primary_language" ]] && primary_language="python"
fi

if has_file "Cargo.toml"; then
  languages+=("rust")
  [[ -z "$primary_language" ]] && primary_language="rust"
fi

if has_file "go.mod"; then
  languages+=("go")
  [[ -z "$primary_language" ]] && primary_language="go"
fi

if has_file "Gemfile" || has_glob "*.rb"; then
  languages+=("ruby")
  [[ -z "$primary_language" ]] && primary_language="ruby"
fi

if has_glob "*.csproj" || has_file "*.sln"; then
  languages+=("csharp")
  [[ -z "$primary_language" ]] && primary_language="csharp"
fi

if has_file "pom.xml" || has_file "build.gradle" || has_file "build.gradle.kts"; then
  languages+=("java")
  [[ -z "$primary_language" ]] && primary_language="java"
fi

# Shell scripts in ~/.claude context
if has_glob "*.sh" || has_glob "**/*.sh"; then
  languages+=("shell")
  [[ -z "$primary_language" ]] && primary_language="shell"
fi

# --- Framework Detection ---

frameworks=()

if has_file "package.json"; then
  pkg_content=$(cat "$REPO_ROOT/package.json" 2>/dev/null || echo "{}")

  # Node.js frameworks
  if echo "$pkg_content" | grep -q '"next"'; then frameworks+=("next.js"); fi
  if echo "$pkg_content" | grep -q '"react"'; then frameworks+=("react"); fi
  if echo "$pkg_content" | grep -q '"vue"'; then frameworks+=("vue"); fi
  if echo "$pkg_content" | grep -q '"svelte"'; then frameworks+=("svelte"); fi
  if echo "$pkg_content" | grep -q '"express"'; then frameworks+=("express"); fi
  if echo "$pkg_content" | grep -q '"fastify"'; then frameworks+=("fastify"); fi
  if echo "$pkg_content" | grep -q '"nestjs"' || echo "$pkg_content" | grep -q '"@nestjs/core"'; then frameworks+=("nestjs"); fi
  if echo "$pkg_content" | grep -q '"nuxt"'; then frameworks+=("nuxt"); fi
  if echo "$pkg_content" | grep -q '"astro"'; then frameworks+=("astro"); fi
  if echo "$pkg_content" | grep -q '"remix"' || echo "$pkg_content" | grep -q '"@remix-run"'; then frameworks+=("remix"); fi
fi

if has_file "pyproject.toml" || has_file "requirements.txt"; then
  py_deps=""
  [[ -f "$REPO_ROOT/pyproject.toml" ]] && py_deps+=$(cat "$REPO_ROOT/pyproject.toml" 2>/dev/null)
  [[ -f "$REPO_ROOT/requirements.txt" ]] && py_deps+=$(cat "$REPO_ROOT/requirements.txt" 2>/dev/null)

  if echo "$py_deps" | grep -qi "django"; then frameworks+=("django"); fi
  if echo "$py_deps" | grep -qi "flask"; then frameworks+=("flask"); fi
  if echo "$py_deps" | grep -qi "fastapi"; then frameworks+=("fastapi"); fi
fi

# --- Package Manager Detection ---

package_managers=()
has_lockfile="false"

if has_file "package-lock.json"; then
  package_managers+=("npm")
  has_lockfile="true"
elif has_file "yarn.lock"; then
  package_managers+=("yarn")
  has_lockfile="true"
elif has_file "pnpm-lock.yaml"; then
  package_managers+=("pnpm")
  has_lockfile="true"
elif has_file "bun.lockb" || has_file "bun.lock"; then
  package_managers+=("bun")
  has_lockfile="true"
elif has_file "package.json"; then
  package_managers+=("npm")
fi

if has_file "Pipfile.lock"; then
  package_managers+=("pipenv")
  has_lockfile="true"
elif has_file "poetry.lock"; then
  package_managers+=("poetry")
  has_lockfile="true"
elif has_file "requirements.txt"; then
  package_managers+=("pip")
fi

if has_file "Cargo.lock"; then
  package_managers+=("cargo")
  has_lockfile="true"
elif has_file "Cargo.toml"; then
  package_managers+=("cargo")
fi

if has_file "go.sum"; then
  package_managers+=("go")
  has_lockfile="true"
elif has_file "go.mod"; then
  package_managers+=("go")
fi

if has_file "Gemfile.lock"; then
  package_managers+=("bundler")
  has_lockfile="true"
elif has_file "Gemfile"; then
  package_managers+=("bundler")
fi

# --- CI/CD Detection ---

has_ci="false"
ci_provider=""

if has_dir ".github/workflows"; then
  has_ci="true"
  ci_provider="github-actions"
elif has_file ".gitlab-ci.yml"; then
  has_ci="true"
  ci_provider="gitlab-ci"
elif has_dir ".circleci"; then
  has_ci="true"
  ci_provider="circleci"
elif has_file "Jenkinsfile"; then
  has_ci="true"
  ci_provider="jenkins"
elif has_file ".travis.yml"; then
  has_ci="true"
  ci_provider="travis"
elif has_file "azure-pipelines.yml"; then
  has_ci="true"
  ci_provider="azure-devops"
fi

# --- Docker Detection ---

has_docker="false"
if has_file "Dockerfile" || has_file "docker-compose.yml" || has_file "docker-compose.yaml" || has_file "compose.yml"; then
  has_docker="true"
fi

# --- Test Framework Detection ---

test_frameworks=()
has_tests="false"

if has_file "package.json"; then
  pkg_content=$(cat "$REPO_ROOT/package.json" 2>/dev/null || echo "{}")

  if echo "$pkg_content" | grep -q '"vitest"'; then
    test_frameworks+=("vitest")
    has_tests="true"
  fi
  if echo "$pkg_content" | grep -q '"jest"'; then
    test_frameworks+=("jest")
    has_tests="true"
  fi
  if echo "$pkg_content" | grep -q '"mocha"'; then
    test_frameworks+=("mocha")
    has_tests="true"
  fi
  if echo "$pkg_content" | grep -q '"playwright"' || echo "$pkg_content" | grep -q '"@playwright"'; then
    test_frameworks+=("playwright")
    has_tests="true"
  fi
  if echo "$pkg_content" | grep -q '"cypress"'; then
    test_frameworks+=("cypress")
    has_tests="true"
  fi
fi

# Python test frameworks
if has_file "pytest.ini" || has_file "pyproject.toml" || has_dir "tests"; then
  if has_file "pyproject.toml" && grep -q "pytest" "$REPO_ROOT/pyproject.toml" 2>/dev/null; then
    test_frameworks+=("pytest")
    has_tests="true"
  elif has_file "pytest.ini" || has_file "conftest.py"; then
    test_frameworks+=("pytest")
    has_tests="true"
  fi
fi

# Rust
if has_file "Cargo.toml"; then
  # Rust has built-in test support
  if grep -rq "#\[cfg(test)\]\|#\[test\]" "$REPO_ROOT/src/" 2>/dev/null; then
    test_frameworks+=("cargo-test")
    has_tests="true"
  fi
fi

# Go
if has_file "go.mod" && has_glob "**/*_test.go"; then
  test_frameworks+=("go-test")
  has_tests="true"
fi

# Detect test directories as fallback
if [[ "$has_tests" == "false" ]]; then
  if has_dir "test" || has_dir "tests" || has_dir "__tests__" || has_dir "spec"; then
    has_tests="true"
  fi
fi

# --- Git Remote ---

git_remote=""
if [[ -d "$REPO_ROOT/.git" ]] || git -C "$REPO_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  git_remote=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")
  # Normalize git@ to https format for display
  if [[ "$git_remote" == git@* ]]; then
    git_remote=$(echo "$git_remote" | sed 's|git@\(.*\):\(.*\)\.git|https://\1/\2|; s|\.git$||')
  fi
fi

# --- File Counts ---

file_count=0
source_file_count=0

if command -v find > /dev/null 2>&1; then
  file_count=$(find "$REPO_ROOT" -type f \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/vendor/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/target/*' \
    -not -path '*/.next/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    2>/dev/null | wc -l | tr -d ' ')

  source_file_count=$(find "$REPO_ROOT" -type f \
    \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
       -o -name "*.py" -o -name "*.rs" -o -name "*.go" -o -name "*.rb" \
       -o -name "*.java" -o -name "*.cs" -o -name "*.sh" -o -name "*.bash" \
       -o -name "*.vue" -o -name "*.svelte" \) \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/vendor/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/target/*' \
    -not -path '*/.next/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    2>/dev/null | wc -l | tr -d ' ')
fi

# --- Output JSON ---

cat <<ENDJSON
{
  "languages": $(json_array ${languages[@]+"${languages[@]}"}),
  "primary_language": "$primary_language",
  "frameworks": $(json_array ${frameworks[@]+"${frameworks[@]}"}),
  "package_managers": $(json_array ${package_managers[@]+"${package_managers[@]}"}),
  "has_lockfile": $(json_bool "$has_lockfile"),
  "has_ci": $(json_bool "$has_ci"),
  "ci_provider": "$ci_provider",
  "has_docker": $(json_bool "$has_docker"),
  "has_tests": $(json_bool "$has_tests"),
  "test_frameworks": $(json_array ${test_frameworks[@]+"${test_frameworks[@]}"}),
  "repo_root": "$REPO_ROOT",
  "git_remote": "$git_remote",
  "file_count": $file_count,
  "source_file_count": $source_file_count
}
ENDJSON
