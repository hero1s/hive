<?xml version="1.0" encoding="utf-8"?>
{{% local ALIBS = {} %}}
{{% local STDAFX = nil %}}
{{% local AINCLUDES = {} %}}
{{% local ALIBDIRS = {} %}}
{{% for _, CLIB in pairs(LIBS or {}) do %}}
{{% table.insert(ALIBS, CLIB .. ".lib") %}}
{{% end %}}
{{% for _, WLIB in pairs(WINDOWS_LIBS or {}) do %}}
{{% table.insert(ALIBS, WLIB) %}}
{{% end %}}
{{% for _, DDEF in pairs(WINDOWS_DEFINES or {}) do %}}
{{% table.insert(DEFINES, DDEF) %}}
{{% end %}}
{{% for _, WINC in pairs(WINDOWS_INCLUDES or {}) do %}}
{{% table.insert(INCLUDES, WINC) %}}
{{% end %}}
{{% for _, WLDIR in pairs(WINDOWS_LIBRARY_DIR or {}) do %}}
{{% table.insert(LIBRARY_DIR, WLDIR) %}}
{{% end %}}
{{% if MIMALLOC and MIMALLOC_DIR then %}}
{{% table.insert(ALIBS, "mimalloc.lib") %}}
{{% table.insert(INCLUDES, "$(SolutionDir)" .. MIMALLOC_DIR) %}}
{{% end %}}
{{% local FMT_LIBS = table.concat(ALIBS, ";") %}}
{{% local FMT_DEFINES = table.concat(DEFINES or {}, ";") %}}
{{% for _, INC in pairs(INCLUDES or {}) do %}}
{{% local C_INC = string.gsub(INC, '/', '\\') %}}
{{% table.insert(AINCLUDES, C_INC) %}}
{{% end %}}
{{% for _, LIB_DIR in pairs(LIBRARY_DIR or {}) do %}}
{{% local C_LIB_DIR = string.gsub(LIB_DIR, '/', '\\') %}}
{{% table.insert(ALIBDIRS, C_LIB_DIR) %}}
{{% end %}}
{{% local FMT_INCLUDES = table.concat(AINCLUDES, ";") %}}
{{% local FMT_LIBRARY_DIR = table.concat(ALIBDIRS, ";") %}}
{{% local ARGS = {AUTO_SUB_DIR = AUTO_SUB_DIR, SUB_DIR = SUB_DIR, OBJS = OBJS, EXCLUDE_FILE = EXCLUDE_FILE } %}}
{{% local CINCLUDES, CSOURCES = COLLECT_SOURCES(WORK_DIR, SRC_DIR, ARGS) %}}
<Project DefaultTargets="Build" ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
    <ProjectConfiguration Include="Develop|x64">
      <Configuration>Develop</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
  </ItemGroup>
  <ItemGroup>
  {{% for _, CINC in pairs(CINCLUDES or {}) do %}}
    <ClInclude Include="{{%= CINC[1] %}}"/>
  {{% end %}}
  </ItemGroup>
  <ItemGroup>
  {{% for _, CSRC in pairs(CSOURCES or {}) do %}}
  {{% if string.match(CSRC[1], "stdafx.cpp") then %}}
    {{% STDAFX = true %}}
    <ClCompile Include="{{%= CSRC[1] %}}">
      <PrecompiledHeader Condition="'$(Configuration)|$(Platform)'=='Develop|x64'">Create</PrecompiledHeader>
    </ClCompile>
  {{% else %}}
    {{% if CSRC[4] or (#OBJS == 0 and not CSRC[3]) then %}}
    <ClCompile Include="{{%= CSRC[1] %}}"/>
    {{% else %}}
    <ClCompile Include="{{%= CSRC[1] %}}">
      <ExcludedFromBuild Condition="'$(Configuration)|$(Platform)'=='Develop|x64'">true</ExcludedFromBuild>
    </ClCompile>
    {{% end %}}
  {{% end %}}
  {{% end %}}
  </ItemGroup>
  <PropertyGroup Label="Globals">
    <ProjectGuid>{{{%= GUID_NEW(PROJECT_NAME) %}}}</ProjectGuid>
    <RootNamespace>{{%= PROJECT_NAME %}}</RootNamespace>
    <Keyword>Win32Proj</Keyword>
    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>
    <ProjectName>{{%= PROJECT_NAME %}}</ProjectName>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />
  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Develop|x64'" Label="Configuration">
    {{% if PROJECT_TYPE == "dynamic" then %}}
    <ConfigurationType>DynamicLibrary</ConfigurationType>
    {{% elseif PROJECT_TYPE == "static" then %}}
    <ConfigurationType>StaticLibrary</ConfigurationType>
    {{% else %}}
    <ConfigurationType>Application</ConfigurationType>
    <WholeProgramOptimization>true</WholeProgramOptimization>
    {{% end %}}
    <PlatformToolset>v142</PlatformToolset>
    <CharacterSet>MultiByte</CharacterSet>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
  <ImportGroup Label="ExtensionSettings">
  </ImportGroup>
  <ImportGroup Condition="'$(Configuration)|$(Platform)'=='Develop|x64'" Label="PropertySheets">
    <Import Project="$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props" Condition="exists('$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props')" Label="LocalAppDataPlatform" />
  </ImportGroup>
  <PropertyGroup Label="UserMacros" />
  <PropertyGroup>
    <_ProjectFileVersion>11.0.50727.1</_ProjectFileVersion>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Develop|x64'">
    <TargetName>{{%= TARGET_NAME %}}</TargetName>
    <OutDir>$(SolutionDir)temp\bin\$(Platform)\</OutDir>
    <IntDir>$(SolutionDir)temp\$(ProjectName)\$(Platform)\</IntDir>
  </PropertyGroup>
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Develop|x64'">
    <ClCompile>
      <Optimization>Disabled</Optimization>
      <AdditionalIncludeDirectories>{{%= FMT_INCLUDES %}};%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
      <PreprocessorDefinitions>WIN32;NDEBUG;_WINDOWS;_CRT_SECURE_NO_WARNINGS;{{%= FMT_DEFINES %}};%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <BasicRuntimeChecks>Default</BasicRuntimeChecks>
      <RuntimeLibrary>MultiThreadedDLL</RuntimeLibrary>
      {{% if STDAFX then %}}
      <PrecompiledHeader>Use</PrecompiledHeader>
      {{% else %}}
      <PrecompiledHeader></PrecompiledHeader>
      {{% end %}}
      <WarningLevel>Level3</WarningLevel>
      <DebugInformationFormat>ProgramDatabase</DebugInformationFormat>
      <CompileAs>Default</CompileAs>
      {{% if MIMALLOC and MIMALLOC_DIR then %}}
      <ForcedIncludeFiles>..\..\mimalloc-ex.h</ForcedIncludeFiles>
      {{% end %}}
      {{% if STDCPP == "c++17" then %}}
      <LanguageStandard>stdcpp17</LanguageStandard>
      {{% end %}}
      {{% if STDCPP == "c++20" then %}}
      <LanguageStandard>stdcpp20</LanguageStandard>
      {{% end %}}
    </ClCompile>
    {{% if PROJECT_TYPE == "static" then %}}
    <Lib>
      <AdditionalLibraryDirectories>
      </AdditionalLibraryDirectories>
      <AdditionalDependencies>
      </AdditionalDependencies>
    </Lib>
    {{% else %}}
    <Link>
      <OutputFile>$(OutDir)$(TargetName)$(TargetExt)</OutputFile>
      <AdditionalLibraryDirectories>$(SolutionDir){{%= DST_LIB_DIR %}}\$(Platform);{{%= FMT_LIBRARY_DIR %}};%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
      <GenerateDebugInformation>true</GenerateDebugInformation>
      <SubSystem>Console</SubSystem>
      <ImportLibrary>$(SolutionDir){{%= DST_LIB_DIR %}}\$(Platform)\$(TargetName).lib</ImportLibrary>
      <ProgramDatabaseFile>$(SolutionDir)temp\$(ProjectName)\$(Platform)\$(TargetName).pdb</ProgramDatabaseFile>
      <AdditionalDependencies>{{%= FMT_LIBS %}};%(AdditionalDependencies)</AdditionalDependencies>
      <ForceFileOutput>
      </ForceFileOutput>
    </Link>
    {{% end %}}
    <PreBuildEvent>
      {{% if next(WINDOWS_PREBUILDS) then %}}
      {{% local pre_commands = {} %}}
      {{% for _, PREBUILD_CMD in pairs(WINDOWS_PREBUILDS) do %}}
      {{% local pre_build_cmd = string.gsub(PREBUILD_CMD[2], '/', '\\') %}}
      {{% table.insert(pre_commands, string.format("%s %s", PREBUILD_CMD[1], pre_build_cmd)) %}}
      {{% end %}}
      {{%= string.format("<Command>%s</Command>", table.concat(pre_commands, "\n")) %}}
      {{% end %}}
    </PreBuildEvent>
    <PostBuildEvent>
      {{% local post_commands = {} %}}
      {{% if PROJECT_TYPE == "static" then %}}
      {{% local dst_lib_dir = string.format("$(SolutionDir)%s/$(Platform)", DST_LIB_DIR) %}}
      {{% local dst_dir = string.gsub(dst_lib_dir, '/', '\\') %}}
      {{% table.insert(post_commands, string.format("copy /y $(TargetPath) %s", dst_dir)) %}}
      {{% else %}}
      {{% local dst_dir = string.gsub(DST_DIR, '/', '\\') %}}
      {{% table.insert(post_commands, string.format("copy /y $(TargetPath) $(SolutionDir)%s", dst_dir)) %}}
      {{% end %}}
      {{% for _, POSTBUILD_CMD in pairs(WINDOWS_POSTBUILDS) do %}}
      {{% local post_build_cmd = string.gsub(POSTBUILD_CMD[2], '/', '\\') %}}
      {{% table.insert(post_commands, string.format("%s %s", POSTBUILD_CMD[1], post_build_cmd)) %}}
      {{% end %}}
      {{%= string.format("<Command>%s</Command>", table.concat(post_commands, "\n")) %}}
    </PostBuildEvent>
  </ItemDefinitionGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
  <ImportGroup Label="ExtensionTargets">
  </ImportGroup>
</Project>