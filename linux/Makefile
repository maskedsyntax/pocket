# CXX = g++
# CXXFLAGS = -std=c++17 `pkg-config --cflags gtkmm-3.0` -Wall
# LDFLAGS = `pkg-config --libs gtkmm-3.0`
# TARGET = bin/pocket
# SOURCES = src/main.cpp src/pocket.cpp
# HEADERS = src/pocket.h

# $(TARGET): $(SOURCES) $(HEADERS)
# 	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SOURCES) $(LDFLAGS)

# clean:
# 	rm -f $(TARGET)

# .PHONY: clean


CXX = g++
CXXFLAGS = -std=c++17 `pkg-config --cflags gtkmm-3.0` -Wall
LDFLAGS = `pkg-config --libs gtkmm-3.0`
TARGET = bin/pocket
SOURCES = src/main.cpp src/pocket.cpp src/config.cpp
OBJECTS = $(SOURCES:.cpp=.o)
HEADERS = src/pocket.h src/config.h

$(TARGET): $(OBJECTS) | bin
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJECTS) $(LDFLAGS)

bin:
	mkdir -p bin

%.o: %.cpp $(HEADERS)
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: clean
