
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 16
VisualStudioVersion = 16.0.31313.79
MinimumVisualStudioVersion = 10.0.40219.1
{{% local ALL_PROJS = {} %}}
{{% local ALL_GUID = GUID_NEW("@g" .. "all") %}}
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "all", "all", "{{{%= ALL_GUID %}}}"
EndProject
{{% for _, GROUP in pairs(GROUPS or {}) do %}}
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "{{%= GROUP.NAME %}}", "{{%= GROUP.NAME %}}", "{{{%= GUID_NEW("@g" .. GROUP.NAME) %}}}"
EndProject
{{% for _, PROJECT in ipairs(GROUP.PROJECTS or {}) do %}}
{{% table.insert(ALL_PROJS, PROJECT) %}}
{{% local PROJECT_DIR = string.gsub(PROJECT.DIR, '/', '\\') %}}
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "{{%= PROJECT.NAME %}}", "{{%= PROJECT_DIR %}}\{{%= PROJECT.FILE %}}.vcxproj", "{{{%= PROJECT.GUID %}}}"
	{{% if #PROJECT.DEPS > 0 then %}}
	ProjectSection(ProjectDependencies) = postProject
	{{% for _, DEP in ipairs(PROJECT.DEPS or {}) do %}}
		{{{%= GUID_NEW(DEP) %}}} = {{{%= GUID_NEW(DEP) %}}}
	{{% end %}}
	EndProjectSection
	{{% end %}}
EndProject
{{% end %}}
{{% end %}}
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Develop|x64 = Develop|x64
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
	{{% for _, PROJ in pairs(ALL_PROJS or {}) do %}}
		{{{%= PROJ.GUID %}}}.Develop|x64.ActiveCfg = Develop|x64
		{{{%= PROJ.GUID %}}}.Develop|x64.Build.0 = Develop|x64
	{{% end %}}
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
	GlobalSection(NestedProjects) = preSolution
	{{% for _, PROJ in pairs(ALL_PROJS or {}) do %}}
		{{{%= PROJ.GUID %}}} = {{{%= GUID_NEW("@g" .. PROJ.GROUP) %}}}
	{{% end %}}
	{{% for _, GROUP in pairs(GROUPS or {}) do %}}
		{{{%= GUID_NEW("@g" .. GROUP.NAME) %}}} = {{{%= ALL_GUID %}}}
	{{% end %}}
	EndGlobalSection
	GlobalSection(ExtensibilityGlobals) = postSolution
		SolutionGuid = {63D02246-6BAD-4132-9325-6DDF29305452}
	EndGlobalSection
EndGlobal
