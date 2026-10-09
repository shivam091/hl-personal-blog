/*
  Lazy, so a page only downloads the controllers its markup actually uses;
  most pages need none, and the list grows with every feature.
*/
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"

lazyLoadControllersFrom("controllers", application)
