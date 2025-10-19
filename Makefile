CXX = g++
CXXFLAGS = -std=c++17 `pkg-config --cflags gtkmm-3.0` -Wall
LDFLAGS = `pkg-config --libs gtkmm-3.0`
TARGET = bin/pod
SOURCES = src/main.cpp src/pod.cpp
HEADERS = src/pod.h

$(TARGET): $(SOURCES) $(HEADERS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SOURCES) $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: clean
