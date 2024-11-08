/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package kafka.test;


import java.io.File;
import java.io.InputStream;
import java.net.URI;
import java.net.URL;
import java.nio.file.FileSystem;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Collections;
import java.util.Iterator;
import java.util.function.Function;
import java.util.stream.Stream;

public class JarResourceLoader {
    public static File loadFileFromResource(Class clazz, String resourcePath) {
        if (System.getenv("BAZEL_TEST") != null) {
            try (InputStream is = clazz.getResource(resourcePath).openStream()) {
                File tempFile = File.createTempFile(resourcePath, null);
                Files.copy(is, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING);

                return tempFile;
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        } else {
            try {
                URL resource = clazz.getResource(resourcePath);
                return new File(resource.toURI());
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }

    public static File loadFileFromResourceWithClassLoader(Class clazz, String resourcePath) {
        if (System.getenv("BAZEL_TEST") != null) {
            try (InputStream is = clazz.getClassLoader().getResource(resourcePath).openStream()) {
                File tempFile = File.createTempFile(resourcePath, null);
                Files.copy(is, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                return tempFile;
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        } else {
            try {
                URL resource = clazz.getClassLoader().getResource(resourcePath);
                return new File(resource.toURI());
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }

    public static File loadDirectoryFromResource(ClassLoader loader, String resourcePath) {
        return loadDirectoryFromResource(loader::getResource, resourcePath);
    }

    public static File loadDirectoryFromResource(Class clazz, String resourcePath) {
        return loadDirectoryFromResource(clazz::getResource, resourcePath);
    }

    public static File loadDirectoryFromResource(Function<String, URL> getResource, String resourcePath) {
        if (System.getenv("BAZEL_TEST") != null) {
            try {
                Path tempDir = Files.createTempDirectory("resources");

                URI uri = getResource.apply(resourcePath).toURI();
                FileSystem fileSystem = FileSystems.newFileSystem(uri, Collections.<String, Object>emptyMap());
                Path newPath = fileSystem.getPath(resourcePath);
                Stream<Path> walk = Files.walk(newPath, 10);
                for (Iterator<Path> it = walk.iterator(); it.hasNext(); ) {
                    Path filePath = it.next();
                    if (Files.isDirectory(filePath)) {
                        continue;
                    }

                    File tempFile = new File(Paths.get(tempDir.toString(), filePath.toString()).toUri());
                    Path baseDir = Paths.get(tempFile.getParent());
                    if (!Files.exists(baseDir)) {
                        Files.createDirectories(baseDir);
                    }

                    try (InputStream isf = getResource.apply(filePath.toString()).openStream()) {
                        Files.copy(isf, tempFile.toPath());
                    }
                }
                fileSystem.close();

                return new File(Paths.get(tempDir.toString(), resourcePath).toUri());
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        } else {
            try {
                URL resource = getResource.apply(resourcePath);
                return new File(resource.toURI());
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }
}
