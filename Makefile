SDSL_DIR=../sdsl-lite

# In OS X, getrusage() returns maximum resident set size in bytes.
# In Linux, the value is in kilobytes, so this line should be commented out.
#RUSAGE_FLAGS=-DRUSAGE_IN_BYTES

# Multithreading with OpenMP and libstdc++ Parallel Mode.
PARALLEL_FLAGS=-fopenmp -pthread
# Turn off libstdc++ parallel mode for clang
ifneq (clang,$(findstring clang,$(shell $(CXX) --version)))
PARALLEL_FLAGS+=-D_GLIBCXX_PARALLEL
endif

OTHER_FLAGS=$(RUSAGE_FLAGS) $(PARALLEL_FLAGS)

include $(SDSL_DIR)/Make.helper
CXX_FLAGS=$(MY_CXX_FLAGS) $(OTHER_FLAGS) $(MY_CXX_OPT_FLAGS) -I$(INC_DIR) -Iinclude
LIBOBJS=algorithms.o dynamic_gbwt.o files.o gbwt.o internal.o support.o utils.o
SOURCES=$(wildcard *.cpp)
HEADERS=$(wildcard include/gbwt/*.h)
OBJS=$(SOURCES:.cpp=.o)
LIBS=-L$(LIB_DIR) -lsdsl -ldivsufsort -ldivsufsort64
LIBRARY=libgbwt.a
PROGRAMS=prepare_text build_gbwt merge_gbwt benchmark

all: $(LIBRARY) $(PROGRAMS)

%.o:%.cpp $(HEADERS)
	$(MY_CXX) $(CXX_FLAGS) -c $<

$(LIBRARY):$(LIBOBJS)
	ar rcs $@ $(LIBOBJS)

prepare_text:prepare_text.o $(LIBRARY)
	$(MY_CXX) $(CXX_FLAGS) -o $@ $< $(LIBRARY) $(LIBS)

build_gbwt:build_gbwt.o $(LIBRARY)
	$(MY_CXX) $(CXX_FLAGS) -o $@ $< $(LIBRARY) $(LIBS)

merge_gbwt:merge_gbwt.o $(LIBRARY)
	$(MY_CXX) $(CXX_FLAGS) -o $@ $< $(LIBRARY) $(LIBS)

benchmark:benchmark.o $(LIBRARY)
	$(MY_CXX) $(CXX_FLAGS) -o $@ $< $(LIBRARY) $(LIBS)

clean:
	rm -f $(PROGRAMS) $(OBJS) $(LIBRARY)
