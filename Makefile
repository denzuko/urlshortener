TARGET	:= microservice
PREFIX	:= usr/local
BUILDROOT	:= build/$(PREFIX)/bin

all: $(TARGET).tgz

$(BUILDROOT):
	@mkdir -p $@

$(BUILDROOT)/$(TARGET): $(BUILDROOT)
	@ros dump executable $(TARGET).ros -o $@

build/$(PREFIX)/man/man1:
	@pandoc -s -t man build/microservice.md -o $<

$(TARGET).tgz: $(BUILDROOT)/$(TARGET)
	@tar zcvf $@ -C build $(shell echo "$(PREFIX)" | cut -d/ -f1)

install: $(TARGET).tgz
	@tar -C / -xzvf $<

clean:
	@rm -Rf build

distclean: clean
	@rm $(TARGET).tgz .*.swp
