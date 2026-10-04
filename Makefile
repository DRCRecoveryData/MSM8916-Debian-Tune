.PHONY: check install

check:
	@for f in *.sh; do bash -n $$f && echo "OK: $$f"; done

install:
	@sudo install -m 755 upgrade-to-trixie.sh /root/
	@sudo install -m 755 tune-openstick.sh /root/
	@sudo install -m 755 verify.sh /root/
	@echo "Installed to /root/"
