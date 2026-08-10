TARGET	:= microservice
PREFIX	:= usr/local
BUILDROOT	:= build/$(PREFIX)/bin
MANROOT	:= build/$(PREFIX)/man/man1

all: test doc $(TARGET).tgz

$(BUILDROOT):
	@mkdir -p $@

$(MANROOT):
	@mkdir -p $@

$(BUILDROOT)/$(TARGET): $(BUILDROOT)
	@ros dump executable $(TARGET).ros -o $@

build/$(TARGET).md: $(TARGET).ros docs.ros
	@ros docs.ros

$(MANROOT)/$(TARGET).1: build/$(TARGET).md $(MANROOT)
	@pandoc -s -t man build/microservice.md -o $@

$(TARGET).tgz: $(BUILDROOT)/$(TARGET)
	@tar zcvf $@ -C build $(shell echo "$(PREFIX)" | cut -d/ -f1)

install: $(TARGET).tgz
	@tar -C / -xzvf $<

test: tests.ros 
	@ros $<

doc: $(MANROOT)/$(TARGET).1 docs.ros

bin: $(BUILDROOT)/$(TARGET) $(TARGET).ros

clean:
	@-rm -Rf build

distclean: clean
	@-rm $(TARGET).tgz .*.swp
