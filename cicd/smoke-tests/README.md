# Jenkins worker smoke tests

These projects are intentionally tiny infrastructure probes. They are not the real `portfolio-java` or `risk-engine-dotnet` applications.

The Jenkins smoke job validates that the dedicated worker can:

- run on `jenkins-agent-01` rather than the controller;
- execute Java 21/Javac and Maven;
- run a JUnit test and package a JAR;
- execute the .NET 8 SDK and an xUnit test;
- return logs to the controller;
- archive the Java JAR in Jenkins.

The real application implementation remains later in the platform roadmap.
