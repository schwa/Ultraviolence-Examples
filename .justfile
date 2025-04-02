XCODE_PROJECT := "Ultraviolence-Examples.xcodeproj"
XCODE_SCHEME := "Ultraviolence-Examples"
CONFIGURATION := "Debug"

default: list

list:
    just --list

build:
    xcodebuild \
        -scheme "{{ XCODE_SCHEME }}" \
        -configuration "{{ CONFIGURATION }}" \
        -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max,OS=17.0' \
        build | xcpretty
    @echo "✅ Build Success"

test:
    swift test --quiet --package-path Packages/UltraviolenceExamples
    @echo "✅ Test Success"

# push: build test
#     jj bookmark move main --to @-; jj git push --branch main

format:
    swiftlint --fix --format --quiet
    fd --extension metal --extension h --exec clang-format -i {}
